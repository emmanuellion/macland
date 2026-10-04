import ServiceManagement
import SwiftUI

enum SettingsPage: Hashable {
    case general
    case appearance
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

    private init() {}
}

struct SettingsView: View {
    private let navigation = SettingsNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar()
                .frame(width: 250)
                .background(VisualEffectBackground(material: .sidebar))

            ScrollView {
                Group {
                    switch navigation.selection {
                    case .general: GeneralPage()
                    case .appearance: AppearancePage()
                    case .activities: ActivitiesPage()
                    case .module(let id):
                        if let module = ModuleRegistry.shared.module(id: id) { ModulePage(module: module) }
                    }
                }
                // Colonne de lecture centrée : les lignes ne s'étirent pas sur toute la fenêtre.
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.top, 64)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 620)
        .ignoresSafeArea()
        .environment(\.locale, IslandSettings.shared.locale)
    }
}

// MARK: - Barre latérale

private struct SettingsSidebar: View {
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
                .frame(width: 36, height: 36)
                .shadow(color: .purple.opacity(0.25), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Island").font(.system(size: 15, weight: .bold))
                    Text(tr("Réglages", "Settings")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    SidebarItem(page: .general, title: tr("Général", "General"), systemImage: "gearshape.fill", tint: .gray)
                    SidebarItem(page: .appearance, title: tr("Apparence", "Appearance"), systemImage: "paintbrush.pointed.fill", tint: .blue)
                    SidebarItem(page: .activities, title: tr("Activités en direct", "Live Activities"), systemImage: "bolt.fill", tint: .orange)

                    Text(tr("Modules", "Modules"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 22)
                        .padding(.bottom, 6)

                    ForEach(registry.orderedModules, id: \.id) { module in
                        SidebarItem(page: .module(module.id), title: module.name, systemImage: module.systemImage,
                                    tint: module.tint, isOn: registry.isEnabled(module))
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(tr("Quitter Island", "Quit Island"), systemImage: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

private struct SidebarItem: View {
    let page: SettingsPage
    let title: String
    let systemImage: String
    let tint: Color
    var isOn: Bool?

    private let navigation = SettingsNavigation.shared

    var body: some View {
        let selected = navigation.selection == page
        let hovered = navigation.hovered == page

        HStack(spacing: 11) {
            IconTile(systemImage: systemImage, tint: tint, size: 26)
                .saturation(isOn == false ? 0 : 1)
                .opacity(isOn == false ? 0.55 : 1)
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : isOn == false ? .secondary : .primary)
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

private struct PageHeader<Accessory: View>: View {
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

            SettingsCard(tr("Langue", "Language")) {
                PickerRow(tr("Langue de l'app", "App language"),
                          subtitle: tr("« Système » suit la langue de macOS.", "“System” follows the macOS language."),
                          selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
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
                SliderRow(tr("Délai de fermeture", "Close delay"), value: $settings.collapseDelay, range: 0...1.5, step: 0.05, format: Self.seconds)
                ToggleRow(tr("Retour haptique", "Haptic feedback"), subtitle: tr("Petite vibration du trackpad à l'ouverture.", "A light trackpad tap when it opens."), isOn: $settings.hapticFeedback)
            }

            SettingsCard(tr("Affichage", "Display")) {
                ToggleRow(tr("Écrans sans encoche", "Screens without a notch"), subtitle: tr("Affiche aussi une île sur les écrans externes.", "Also shows an island on external displays."),
                          isOn: $settings.showOnScreensWithoutNotch)
                ToggleRow(tr("Icône dans la barre des menus", "Menu bar icon"),
                          subtitle: settings.showMenuBarIcon ? nil : tr("Clic droit sur l'île ou relance l'app pour revenir ici.", "Right-click the island or relaunch the app to come back here."),
                          isOn: $settings.showMenuBarIcon)
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

            SettingsCard(tr("Couleur", "Color"), footer: tr("Fermée, l'île reste noire pour se fondre dans l'encoche de la caméra.", "When closed, the island stays black to blend into the camera notch.")) {
                SettingsRow(tr("Couleur de l'île ouverte", "Open island color"), subtitle: settings.islandColor.label) {
                    HStack(spacing: 10) {
                        ForEach(IslandColor.allCases) { option in
                            ColorSwatch(option: option, isSelected: settings.islandColor == option) {
                                withAnimation(.smooth(duration: 0.25)) { settings.islandColor = option }
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

            SettingsCard(tr("Dimensions", "Size")) {
                SliderRow(tr("Largeur", "Width"), value: $settings.expandedWidth, range: 400...860, step: 10) { "\(Int($0)) pt" }
                SliderRow(tr("Hauteur", "Height"), value: $settings.expandedHeight, range: 120...320, step: 5) { "\(Int($0)) pt" }
                SliderRow(tr("Arrondi", "Corner radius"), value: $settings.expandedCornerRadius, range: 8...48, step: 1) { "\(Int($0)) pt" }
                ToggleRow(tr("Ombre portée", "Drop shadow"), isOn: $settings.showShadow)
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

            SettingsCard(tr("Disposition", "Layout")) {
                switch module.kind {
                case .widget:
                    PositionRow(module: module, title: tr("Position sur l'accueil", "Position on Home"), unit: tr("de gauche à droite", "left to right"))
                case .page:
                    PositionRow(module: module, title: tr("Position de l'onglet", "Tab position"),
                                unit: tr("parmi les onglets en haut à gauche de l'île ouverte", "among the tabs at the top left of the open island"))
                case .background:
                    SettingsRow(tr("Autour de l'encoche", "Around the notch"),
                                subtitle: tr("S'affiche sous forme d'activité en direct, pas dans l'île ouverte.", "Shows up as a live activity, not in the open island.")) {
                        Image(systemName: "capsule.fill").foregroundStyle(.secondary)
                    }
                }
            }

            if let settingsView = module.settingsView() {
                SettingsCard(tr("Réglages", "Settings")) { settingsView }
                    .disabled(!enabled.wrappedValue)
                    .opacity(enabled.wrappedValue ? 1 : 0.5)
            }
        }
    }
}

/// Flèches pour déplacer un module parmi ceux du même type.
private struct PositionRow: View {
    let module: any IslandModule
    let title: String
    let unit: String
    private let registry = ModuleRegistry.shared

    var body: some View {
        let position = registry.position(of: module)
        SettingsRow(title, subtitle: position.map { tr("\($0.index) sur \($0.count), \(unit)", "\($0.index) of \($0.count), \(unit)") }) {
            ControlGroup {
                Button { registry.move(module, by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(position?.index == 1)
                Button { registry.move(module, by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(position.map { $0.index == $0.count } ?? true)
            }
            .fixedSize()
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
private final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var error: String?

    var isEnabled: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard isEnabled != oldValue else { return }
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
