import ServiceManagement
import SwiftUI

enum SettingsPage: Hashable {
    case general
    case appearance
    case layout
    case activities
    case module(String)
}

/// État de navigation de la fenêtre de réglages (pas de `@State` : macro indisponible sans Xcode).
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    var selection = SettingsPage.general
    var hovered: SettingsPage?
    var previewExpanded = true
    /// Texte de la barre de recherche.
    var query = ""
    /// Tous les réglages trouvables, récoltés par l'index invisible.
    var index: [SearchEntry] = []
    /// Réglage mis en évidence après un clic sur un résultat de recherche.
    var highlighted: String?
    /// Réglage vers lequel faire défiler la page.
    var scrollTarget: String?
    /// Module en cours de glisser-déposer dans la page Disposition.
    var draggedModule: String?

    /// Démarre un glisser. Un glisser annulé (lâché hors d'une zone, Échap) ne prévient pas
    /// SwiftUI : on surveille donc le bouton de la souris pour remettre l'état à zéro.
    func beginDrag(_ id: String) {
        draggedModule = id
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                timer.invalidate()
                if self?.draggedModule == id { self?.draggedModule = nil }
            }
        }
    }
    /// Sections repliées de la barre latérale (mémorisées).
    var collapsedSections: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "settingsCollapsedSections") ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedSections), forKey: "settingsCollapsedSections") }
    }

    func toggleSection(_ id: String) {
        if collapsedSections.contains(id) { collapsedSections.remove(id) } else { collapsedSections.insert(id) }
    }

    private init() {}

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Résultats regroupés par page : les pages les plus pertinentes d'abord, puis l'ordre de la barre latérale.
    var results: [(page: SettingsPage, entries: [SearchEntry])] {
        let matches = index.filter { $0.page != nil && SettingsSearch.matches($0, query: query) }
        var seen = Set<SearchEntry>()
        let unique = matches.filter { seen.insert(SearchEntry(title: $0.title, page: $0.page)).inserted }
        let groups = SettingsPage.ordered.enumerated().compactMap { order, page -> (page: SettingsPage, entries: [SearchEntry], score: Int, order: Int)? in
            let entries = unique.filter { $0.page == page }
                .sorted { SettingsSearch.score($0, query: query) > SettingsSearch.score($1, query: query) }
            guard let best = entries.first else { return nil }
            return (page, entries, SettingsSearch.score(best, query: query), order)
        }
        return groups
            .sorted { ($0.score, -$0.order) > ($1.score, -$1.order) }
            .map { ($0.page, $0.entries) }
    }

    /// Ouvre la page du réglage, y fait défiler et le met en évidence un instant.
    func reveal(_ entry: SearchEntry) {
        guard let page = entry.page else { return }
        selection = page
        query = ""
        scrollTarget = entry.title
        highlighted = entry.title
        let title = entry.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.highlighted == title { self?.highlighted = nil }
        }
    }
}

extension SettingsPage {
    /// Ordre d'affichage : pages générales, puis modules dans l'ordre de la barre latérale.
    @MainActor
    static var ordered: [SettingsPage] {
        [.general, .appearance, .layout, .activities] + SidebarGroup.allCases.flatMap { group in
            group.modules.map { SettingsPage.module($0.id) }
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .general: tr("Général", "General")
        case .appearance: tr("Apparence", "Appearance")
        case .layout: tr("Disposition", "Layout")
        case .activities: tr("Activités en direct", "Live Activities")
        case .module(let id): ModuleRegistry.shared.module(id: id)?.name ?? id
        }
    }

    @MainActor
    var icon: (systemImage: String, tint: Color) {
        switch self {
        case .general: ("gearshape.fill", .gray)
        case .appearance: ("paintbrush.pointed.fill", .blue)
        case .layout: ("rectangle.3.group.fill", .indigo)
        case .activities: ("bolt.fill", .orange)
        case .module(let id):
            ModuleRegistry.shared.module(id: id).map { ($0.systemImage, $0.tint) } ?? ("questionmark", .gray)
        }
    }
}

/// Groupes de modules de la barre latérale, selon l'endroit où ils s'affichent.
enum SidebarGroup: String, CaseIterable {
    case home, tabs, notch, background

    var title: String {
        switch self {
        case .home: tr("Accueil de l'île", "Island home")
        case .tabs: tr("Onglets", "Tabs")
        case .notch: tr("Autour de l'encoche", "Around the notch")
        case .background: tr("En arrière-plan", "In the background")
        }
    }

    @MainActor
    var modules: [any IslandModule] {
        ModuleRegistry.shared.orderedModules.filter { module in
            switch self {
            case .home: module.kind == .widget
            case .tabs: module.kind == .page
            case .notch: module.kind == .background
            case .background: module.kind == .service
            }
        }
    }
}

struct SettingsView: View {
    private let navigation = SettingsNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar()
                .frame(width: 260)
                .background(VisualEffectBackground(material: .sidebar))

            ScrollViewReader { proxy in
                ScrollView {
                    page(navigation.selection)
                        // Colonne de lecture centrée : les lignes ne s'étirent pas sur toute la fenêtre.
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(.horizontal, 44)
                        .padding(.top, 60)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity)
                        .id(navigation.selection)
                }
                .scrollIndicators(.automatic)
                .background(Color(nsColor: .windowBackgroundColor))
                .onChange(of: navigation.scrollTarget) { _, target in
                    guard let target else { return }
                    // La nouvelle page doit être affichée et mise en page avant de défiler :
                    // on réessaie un peu plus tard pour les réglages tout en bas des longues pages.
                    for delay in [0.1, 0.35] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            withAnimation(.smooth) { proxy.scrollTo(target, anchor: .center) }
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { navigation.scrollTarget = nil }
                }
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .ignoresSafeArea()
        .environment(\.locale, IslandSettings.shared.locale)
        .background(alignment: .topLeading) {
            // Index invisible pour la recherche : toutes les pages, rendues hors écran.
            if navigation.isSearching { SearchIndexer() }
        }
    }

    @ViewBuilder
    fileprivate func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralPage()
        case .appearance: AppearancePage()
        case .layout: LayoutPage()
        case .activities: ActivitiesPage()
        case .module(let id):
            if let module = ModuleRegistry.shared.module(id: id) { ModulePage(module: module) }
        }
    }
}

/// Affiche toutes les pages de façon invisible pour récolter les réglages trouvables.
private struct SearchIndexer: View {
    var body: some View {
        VStack {
            ForEach(SettingsPage.ordered, id: \.self) { page in
                SettingsView().page(page)
                    .searchPage(page)
            }
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(width: 0, height: 0)
        .clipped()
        .onPreferenceChange(SearchEntriesKey.self) { entries in
            SettingsNavigation.shared.index = entries
        }
    }
}

// MARK: - Barre latérale

private struct SettingsSidebar: View {
    @Bindable private var navigation = SettingsNavigation.shared
    private let registry = ModuleRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    NotchShape(topRadius: 2.5, bottomRadius: 4)
                        .fill(.black)
                        .frame(width: 20, height: 7)
                }
                .frame(width: 34, height: 34)
                .shadow(color: .purple.opacity(0.25), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("macland").font(.system(size: 15, weight: .bold))
                    Text(tr("Réglages", "Settings")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 54)
            .padding(.bottom, 16)

            SearchField(text: $navigation.query)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            ScrollView {
                if navigation.isSearching {
                    SearchResults()
                        .padding(.horizontal, 12)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        SidebarHeader(id: "settings", title: tr("Réglages", "Settings"))
                        if !navigation.collapsedSections.contains("settings") {
                            SidebarItem(page: .general)
                            SidebarItem(page: .appearance)
                            SidebarItem(page: .layout)
                            SidebarItem(page: .activities)
                        }

                        ForEach(SidebarGroup.allCases, id: \.self) { group in
                            let modules = group.modules
                            if !modules.isEmpty {
                                SidebarHeader(id: group.rawValue, title: group.title, count: modules.count)
                                if !navigation.collapsedSections.contains(group.rawValue) {
                                    ForEach(modules, id: \.id) { module in
                                        SidebarItem(page: .module(module.id), isOn: registry.isEnabled(module))
                                    }
                                }
                            }
                        }
                    }
                    .animation(.smooth(duration: 0.2), value: navigation.collapsedSections)
                    .padding(.horizontal, 12)
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(tr("Quitter macland", "Quit macland"), systemImage: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }
}

/// En-tête de section repliable (clic pour ouvrir / fermer).
private struct SidebarHeader: View {
    let id: String
    let title: String
    var count: Int?
    private let navigation = SettingsNavigation.shared

    var body: some View {
        let collapsed = navigation.collapsedSections.contains(id)
        Button {
            navigation.toggleSection(id)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                if collapsed, let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? tr("Afficher la section", "Show section") : tr("Masquer la section", "Hide section"))
    }
}

/// Champ de recherche arrondi, avec bouton d'effacement.
private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(tr("Rechercher un réglage", "Search settings"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SearchResults: View {
    private let navigation = SettingsNavigation.shared

    var body: some View {
        let results = navigation.results
        VStack(alignment: .leading, spacing: 4) {
            if results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.tertiary)
                    Text(tr("Aucun réglage trouvé", "No matching settings"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            }
            ForEach(results, id: \.page) { group in
                HStack(spacing: 8) {
                    IconTile(systemImage: group.page.icon.systemImage, tint: group.page.icon.tint, size: 18)
                    Text(group.page.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                ForEach(group.entries, id: \.self) { entry in
                    SearchResultRow(entry: entry)
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let entry: SearchEntry
    private let navigation = SettingsNavigation.shared

    var body: some View {
        Button {
            navigation.reveal(entry)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let section = entry.section {
                    Text(section)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarItem: View {
    let page: SettingsPage
    var isOn: Bool?

    private let navigation = SettingsNavigation.shared

    var body: some View {
        let selected = navigation.selection == page
        let hovered = navigation.hovered == page
        let icon = page.icon

        HStack(spacing: 11) {
            IconTile(systemImage: icon.systemImage, tint: icon.tint, size: 26)
                .saturation(isOn == false ? 0 : 1)
                .opacity(isOn == false ? 0.55 : 1)
            Text(page.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : isOn == false ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            if let isOn {
                Circle()
                    .fill(isOn ? Color.green : Color.primary.opacity(0.15))
                    .frame(width: 6, height: 6)
                    .help(isOn ? tr("Activé", "On") : tr("Désactivé", "Off"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovered ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { navigation.selection = page }
        .onHover { inside in
            if inside { navigation.hovered = page } else if navigation.hovered == page { navigation.hovered = nil }
        }
    }
}

// MARK: - En-tête de page

struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    init(_ title: String, subtitle: String, systemImage: String, tint: Color,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            IconTile(systemImage: systemImage, tint: tint, size: 56)
                .shadow(color: tint.opacity(0.3), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            accessory
        }
        .padding(.bottom, 10)
        .searchable(title, detail: subtitle)
    }
}

// MARK: - Général

private struct GeneralPage: View {
    @Bindable private var settings = IslandSettings.shared
    @Bindable private var launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PageHeader(tr("Général", "General"), subtitle: tr("Comment l'île s'ouvre, où elle s'affiche.", "How the island opens and where it appears."),
                       systemImage: "gearshape.fill", tint: .gray)

            SettingsCard(tr("Langue et thème", "Language & theme")) {
                PickerRow(tr("Langue de l'app", "App language"),
                          subtitle: tr("« Système » suit la langue de macOS.", "“System” follows the macOS language."),
                          selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                PickerRow(tr("Thème des réglages", "Settings theme"),
                          subtitle: tr("« Système » suit le mode clair ou sombre de macOS.",
                                       "“System” follows the macOS light or dark mode."),
                          selection: $settings.settingsTheme) {
                    ForEach(SettingsTheme.allCases) { Text($0.label).tag($0) }
                }
            }

            SettingsCard(tr("Ouverture", "Opening")) {
                PickerRow(tr("Ouvrir l'île au", "Open the island on"), selection: $settings.expandTrigger) {
                    ForEach(ExpandTrigger.allCases) { Text($0.label).tag($0) }
                }
                if settings.expandTrigger == .hover {
                    SliderRow(tr("Délai d'ouverture", "Open delay"), subtitle: tr("Évite les ouvertures en passant vers la barre des menus.", "Avoids opening when heading to the menu bar."),
                              value: $settings.hoverDelay, range: 0...1, step: 0.05, format: Self.seconds)
                }
                SliderRow(tr("Zone de détection", "Hover area"),
                          subtitle: tr("Marge autour de l'encoche qui déclenche l'ouverture.", "Margin around the notch that triggers opening."),
                          value: $settings.hoverPadding, range: 0...20, step: 1) { "\(Int($0)) pt" }
                PickerRow(tr("Onglet à l'ouverture", "Tab when opening"), selection: $settings.alwaysOpenOnHome) {
                    Text(tr("Accueil", "Home")).tag(true)
                    Text(tr("Dernier utilisé", "Last used")).tag(false)
                }
                ToggleRow(tr("Retour haptique", "Haptic feedback"), subtitle: tr("Petite vibration du trackpad à l'ouverture.", "A light trackpad tap when it opens."), isOn: $settings.hapticFeedback)
            }

            SettingsCard(tr("Fermeture", "Closing")) {
                SliderRow(tr("Délai de fermeture", "Close delay"), value: $settings.collapseDelay, range: 0...1.5, step: 0.05, format: Self.seconds)
                ToggleRow(tr("Fermer en cliquant ailleurs", "Close when clicking elsewhere"), isOn: $settings.closeOnClickOutside)
            }

            SettingsCard(tr("Affichage", "Display")) {
                ToggleRow(tr("Masquer en plein écran", "Hide in full screen"),
                          subtitle: tr("L'île disparaît quand une app (vidéo, jeu…) passe en plein écran.",
                                       "The island hides when an app (video, game…) goes full screen."),
                          isOn: $settings.hideInFullScreen)
                ToggleRow(tr("Écrans sans encoche", "Screens without a notch"), subtitle: tr("Affiche aussi une île sur les écrans externes.", "Also shows an island on external displays."),
                          isOn: $settings.showOnScreensWithoutNotch)
                ToggleRow(tr("Icône dans la barre des menus", "Menu bar icon"),
                          subtitle: settings.showMenuBarIcon ? nil : tr("Clic droit sur l'île ou relance l'app pour revenir ici.", "Right-click the island or relaunch the app to come back here."),
                          isOn: $settings.showMenuBarIcon)
            }

            SettingsCard(tr("Aide", "Help")) {
                SettingsRow(tr("Écran d'accueil", "Welcome screen"),
                            subtitle: tr("Présentation, choix des modules et autorisations.",
                                         "Introduction, module picker and permissions.")) {
                    Button(tr("Revoir", "Show again")) { IslandCommands.showOnboarding() }
                }
            }

            SettingsCard(tr("Système", "System"), footer: launchAtLogin.error) {
                ToggleRow(tr("Lancer à l'ouverture de session", "Launch at login"),
                          subtitle: tr("Nécessite que l'app soit installée (scripts/build-app.sh --install).", "Requires the app to be installed (scripts/build-app.sh --install)."),
                          isOn: $launchAtLogin.isEnabled)
            }
        }
    }

    static func seconds(_ value: Double) -> String { String(format: "%.2f s", value) }
}

// MARK: - Apparence

private struct AppearancePage: View {
    @Bindable private var settings = IslandSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PageHeader(tr("Apparence", "Appearance"), subtitle: tr("Taille, forme et animation de l'île ouverte.", "Size, shape and animation of the open island."),
                       systemImage: "paintbrush.pointed.fill", tint: .blue) {
                Button(tr("Réinitialiser", "Reset")) { settings.resetAppearance() }
                    .controlSize(.small)
            }

            IslandPreview()

            SettingsCard(tr("Couleur et matière", "Color & material"), footer: tr("Fermée, l'île reste noire pour se fondre dans l'encoche de la caméra.", "When closed, the island stays black to blend into the camera notch.")) {
                SettingsRow(tr("Couleur de l'île ouverte", "Open island color"), subtitle: settings.islandColor.label) {
                    HStack(spacing: 10) {
                        ForEach(IslandColor.allCases) { option in
                            ColorSwatch(option: option, isSelected: settings.islandColor == option) {
                                withAnimation(.smooth(duration: 0.25)) { settings.islandColor = option }
                            }
                        }
                    }
                }
                SettingsRow(tr("Couleur d'accent", "Accent color"),
                            subtitle: tr("Onglet sélectionné, curseurs et barre de progression. ", "Selected tab, sliders and progress bar. ")
                                + settings.islandAccent.label) {
                    HStack(spacing: 8) {
                        ForEach(IslandAccent.allCases) { accent in
                            AccentSwatch(accent: accent, isSelected: settings.islandAccent == accent) {
                                settings.islandAccent = accent
                            }
                        }
                    }
                }
                PickerRow(tr("Matière", "Material"),
                          subtitle: IslandMaterial.isGlassAvailable
                              ? tr("Liquid Glass laisse deviner ce qu'il y a derrière l'île.", "Liquid Glass lets what's behind the island show through.")
                              : tr("Liquid Glass nécessite macOS 26 ou plus récent.", "Liquid Glass requires macOS 26 or later."),
                          selection: $settings.islandMaterial) {
                    Text(tr("Opaque", "Opaque")).tag(IslandMaterial.solid)
                    Text("Liquid Glass").tag(IslandMaterial.glass)
                }
                .disabled(!IslandMaterial.isGlassAvailable)
                if settings.usesGlass {
                    PickerRow(tr("Verre", "Glass"), subtitle: tr("Clair est plus transparent, Standard plus diffus.", "Clear is more transparent, Standard more diffuse."),
                              selection: $settings.glassVariant) {
                        Text(tr("Standard", "Standard")).tag(GlassVariant.regular)
                        Text(tr("Clair", "Clear")).tag(GlassVariant.clear)
                    }
                    SliderRow(tr("Teinte", "Tint"), subtitle: tr("Quantité de couleur posée sur le verre.", "How much color is applied to the glass."),
                              value: $settings.glassTint, range: 0...1, step: 0.05) { "\(Int($0 * 100)) %" }
                }
            }

            SettingsCard(tr("Forme", "Shape")) {
                SliderRow(tr("Largeur", "Width"), value: $settings.expandedWidth, range: 400...860, step: 10) { "\(Int($0)) pt" }
                SliderRow(tr("Hauteur", "Height"), value: $settings.expandedHeight, range: 120...320, step: 5) { "\(Int($0)) pt" }
                SliderRow(tr("Arrondi", "Corner radius"), value: $settings.expandedCornerRadius, range: 8...48, step: 1) { "\(Int($0)) pt" }
            }

            SettingsCard(tr("Détails", "Details")) {
                ToggleRow(tr("Ombre portée", "Drop shadow"), isOn: $settings.showShadow)
                if settings.showShadow {
                    SliderRow(tr("Intensité de l'ombre", "Shadow intensity"), value: $settings.shadowOpacity,
                              range: 0.1...0.9, step: 0.05) { "\(Int($0 * 100)) %" }
                }
                ToggleRow(tr("Contour", "Outline"), subtitle: tr("Fin liseré autour de l'île ouverte.", "Thin outline around the open island."),
                          isOn: $settings.islandBorder)
                ToggleRow(tr("Bouton des réglages", "Settings button"),
                          subtitle: tr("Engrenage en haut à droite de l'île ouverte.", "Gear at the top right of the open island."),
                          isOn: $settings.showSettingsButton)
                ToggleRow(tr("Séparateurs entre widgets", "Widget separators"), subtitle: tr("Filets verticaux entre les éléments de l'accueil.", "Vertical lines between home items."),
                          isOn: $settings.showWidgetSeparators)
            }

            SettingsCard(tr("Animation", "Animation")) {
                SliderRow(tr("Durée", "Duration"), value: $settings.animationResponse, range: 0.15...1, step: 0.01) { String(format: "%.2f s", $0) }
                SliderRow(tr("Rebond", "Bounce"), subtitle: tr("0 = aucun, plus haut = plus élastique.", "0 = none, higher = springier."),
                          value: $settings.animationBounce, range: 0...0.5, step: 0.01) { "\(Int($0 * 100)) %" }
            }
        }
    }
}

/// Aperçu à l'échelle de l'île, qui suit les réglages en direct.
private struct IslandPreview: View {
    private let settings = IslandSettings.shared
    private let navigation = SettingsNavigation.shared
    private let scale: CGFloat = 0.55

    private var notch: CGSize {
        NSScreen.screens.first(where: \.hasNotch).map { NotchGeometry(screen: $0).size } ?? CGSize(width: 185, height: 32)
    }

    var body: some View {
        let expanded = navigation.previewExpanded
        let topRadius = (expanded ? NotchViewModel.expandedTopRadius : NotchViewModel.collapsedTopRadius) * scale
        let size = expanded
            ? CGSize(width: settings.expandedWidth * scale, height: settings.expandedHeight * scale)
            : CGSize(width: notch.width * scale + 2 * topRadius, height: notch.height * scale)
        let animation = Animation.spring(duration: settings.animationResponse, bounce: settings.animationBounce)

        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.2, blue: 0.55), Color(red: 0.85, green: 0.45, blue: 0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: notch.height * scale)
                .frame(maxHeight: .infinity, alignment: .top)

            IslandBackground(shape: NotchShape(topRadius: topRadius,
                                               bottomRadius: (expanded ? settings.expandedCornerRadius
                                                   : NotchViewModel.collapsedBottomRadius) * scale),
                             isExpanded: expanded)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    if expanded {
                        HStack(spacing: 10) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(settings.islandColor.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
                            }
                        }
                        .padding(.horizontal, 22 * scale + topRadius)
                        .padding(.top, notch.height * scale + 10)
                        .padding(.bottom, 14)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                    }
                }
                .shadow(color: .black.opacity(settings.showShadow && expanded ? 0.5 : 0), radius: 10, y: 4)
                .animation(animation, value: expanded)
                .animation(animation, value: size)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                Button {
                    navigation.previewExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + settings.animationResponse + 0.15) {
                        navigation.previewExpanded = true
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(tr("Rejouer l'animation", "Replay animation"))

                Picker("", selection: Binding(get: { navigation.previewExpanded }, set: { navigation.previewExpanded = $0 })) {
                    Text(tr("Fermée", "Closed")).tag(false)
                    Text(tr("Ouverte", "Open")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .controlSize(.small)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(10)
        }
    }
}

/// Pastille de couleur d'accent ; « Neutre » est représenté par un demi noir / blanc.
private struct AccentSwatch: View {
    let accent: IslandAccent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if accent == .neutral {
                    Circle().fill(LinearGradient(colors: [.white, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Circle().fill(accent.color)
                }
            }
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .frame(width: 18, height: 18)
            .padding(3)
            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(accent.label)
    }
}

/// Pastille de couleur sélectionnable.
private struct ColorSwatch: View {
    let option: IslandColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(option.color)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .frame(width: 24, height: 24)
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(option.label)
    }
}

// MARK: - Activités en direct

private struct ActivitiesPage: View {
    @Bindable private var settings = IslandSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PageHeader(tr("Activités en direct", "Live Activities"),
                       subtitle: tr("Informations brèves qui apparaissent de part et d'autre de l'encoche, sans l'ouvrir.", "Short updates shown on either side of the notch, without opening it."),
                       systemImage: "bolt.fill", tint: .orange)

            SettingsCard(footer: tr("Chaque module règle ensuite ses propres activités dans sa page.", "Each module then configures its own activities on its page.")) {
                ToggleRow(tr("Activités en direct", "Live Activities"), isOn: $settings.liveActivitiesEnabled)
            }

            SettingsCard(tr("Sources", "Sources")) {
                SettingsRow(tr("Lecture en cours", "Now Playing"), subtitle: tr("Pochette et égaliseur pendant la lecture.", "Artwork and equalizer while playing."),
                            icon: ("music.note", .pink)) { EmptyView() }
                SettingsRow(tr("Volume & luminosité", "Volume & Brightness"), subtitle: tr("Jauge à chaque changement.", "A gauge on every change."),
                            icon: ("speaker.wave.2.fill", .blue)) { EmptyView() }
                SettingsRow(tr("Caméra & micro", "Camera & Mic"), subtitle: tr("Points vert et orange pendant l'utilisation.", "Green and orange dots while in use."),
                            icon: ("video.fill", .green)) { EmptyView() }
                SettingsRow(tr("Batterie", "Battery"), subtitle: tr("Branchement du chargeur, batterie faible.", "Charger plugged in, low battery."),
                            icon: ("battery.75percent", .green)) { EmptyView() }
                SettingsRow(tr("Calendrier", "Calendar"), subtitle: tr("Rappel avant le début d'un événement.", "Reminder before an event starts."),
                            icon: ("calendar", .red)) { EmptyView() }
            }

            SettingsCard(tr("Essayer", "Try it"), footer: tr("Regarde l'encoche après avoir cliqué.", "Watch the notch after clicking.")) {
                SettingsRow(tr("Exemple de charge", "Charging example")) {
                    Button(tr("Afficher", "Show")) { showSample(charging: true) }.disabled(!settings.liveActivitiesEnabled)
                }
                SettingsRow(tr("Exemple de rappel", "Reminder example")) {
                    Button(tr("Afficher", "Show")) { showSample(charging: false) }.disabled(!settings.liveActivitiesEnabled)
                }
            }
        }
    }

    private func showSample(charging: Bool) {
        let activity = charging
            ? LiveActivity(id: "sample", duration: 4) {
                Image(systemName: "bolt.fill").foregroundStyle(.green)
            } trailing: {
                Text("82 %").foregroundStyle(.green)
            }
            : LiveActivity(id: "sample", duration: 4) {
                HStack(spacing: 5) {
                    Circle().fill(.orange).frame(width: 7, height: 7)
                    Text(tr("Réunion", "Meeting")).lineLimit(1)
                }
            } trailing: {
                Text(tr("dans 5 min", "in 5 min")).foregroundStyle(.orange)
            }
        ActivityCenter.shared.show(activity)
    }
}

// MARK: - Page d'un module

private struct ModulePage: View {
    let module: any IslandModule
    private let registry = ModuleRegistry.shared

    var body: some View {
        let enabled = Binding(get: { registry.isEnabled(module) }, set: { registry.setEnabled($0, for: module) })

        VStack(alignment: .leading, spacing: 32) {
            PageHeader(module.name, subtitle: module.summary, systemImage: module.systemImage, tint: module.tint) {
                HStack(spacing: 10) {
                    Text(enabled.wrappedValue ? tr("Activé", "On") : tr("Désactivé", "Off"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            if module.kind == .widget || module.kind == .page {
                SettingsCard {
                    SettingsRow(tr("Ordre d'affichage", "Display order"),
                                subtitle: module.kind == .widget
                                    ? tr("Organise les widgets de l'accueil dans la page Disposition.", "Arrange home widgets on the Layout page.")
                                    : tr("Organise les onglets de l'île dans la page Disposition.", "Arrange island tabs on the Layout page."),
                                icon: ("rectangle.3.group.fill", .indigo)) {
                        Button(tr("Ouvrir", "Open")) { SettingsNavigation.shared.selection = .layout }
                    }
                }
            }

            if let settingsView = module.settingsView() {
                // Une carte par section (intertitres du module) : plus lisible qu'un long bloc.
                SettingsSections(tr("Réglages", "Settings")) { settingsView }
                    .disabled(!enabled.wrappedValue)
                    .opacity(enabled.wrappedValue ? 1 : 0.5)
            }
        }
    }
}

// MARK: - Utilitaires

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

@Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var error: String?
    /// Incrémenté à chaque changement pour que SwiftUI relise l'état réel.
    private var revision = 0

    /// Toujours l'état réel de macOS : après un échec, ou un changement fait dans Réglages
    /// Système › Ouverture, l'interrupteur reflète ce qui est vraiment enregistré.
    var isEnabled: Bool {
        get {
            _ = revision
            return SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            revision += 1
        }
    }
}
