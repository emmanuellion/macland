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
                    Text("Réglages").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    SidebarItem(page: .general, title: "Général", systemImage: "gearshape.fill", tint: .gray)
                    SidebarItem(page: .appearance, title: "Apparence", systemImage: "paintbrush.pointed.fill", tint: .blue)
                    SidebarItem(page: .activities, title: "Activités en direct", systemImage: "bolt.fill", tint: .orange)

                    Text("Modules")
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
                Label("Quitter Island", systemImage: "power")
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
                    .help(isOn ? "Activé" : "Désactivé")
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
            PageHeader("Général", subtitle: "Comment l'île s'ouvre, où elle s'affiche.",
                       systemImage: "gearshape.fill", tint: .gray)

            SettingsCard("Ouverture") {
                PickerRow("Ouvrir l'île au", selection: $settings.expandTrigger) {
                    ForEach(ExpandTrigger.allCases) { Text($0.label).tag($0) }
                }
                if settings.expandTrigger == .hover {
                    SliderRow("Délai d'ouverture", subtitle: "Évite les ouvertures en passant vers la barre des menus.",
                              value: $settings.hoverDelay, range: 0...1, step: 0.05, format: Self.seconds)
                }
                SliderRow("Délai de fermeture", value: $settings.collapseDelay, range: 0...1.5, step: 0.05, format: Self.seconds)
                ToggleRow("Retour haptique", subtitle: "Petite vibration du trackpad à l'ouverture.", isOn: $settings.hapticFeedback)
            }

            SettingsCard("Affichage") {
                ToggleRow("Écrans sans encoche", subtitle: "Affiche aussi une île sur les écrans externes.",
                          isOn: $settings.showOnScreensWithoutNotch)
                ToggleRow("Icône dans la barre des menus",
                          subtitle: settings.showMenuBarIcon ? nil : "Clic droit sur l'île ou relance l'app pour revenir ici.",
                          isOn: $settings.showMenuBarIcon)
            }

            SettingsCard("Système", footer: launchAtLogin.error) {
                ToggleRow("Lancer à l'ouverture de session",
                          subtitle: "Nécessite que l'app soit installée (scripts/build-app.sh --install).",
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
            PageHeader("Apparence", subtitle: "Taille, forme et animation de l'île ouverte.",
                       systemImage: "paintbrush.pointed.fill", tint: .blue) {
                Button("Réinitialiser") { settings.resetAppearance() }
                    .controlSize(.small)
            }

            IslandPreview()

            SettingsCard("Dimensions") {
                SliderRow("Largeur", value: $settings.expandedWidth, range: 400...860, step: 10) { "\(Int($0)) pt" }
                SliderRow("Hauteur", value: $settings.expandedHeight, range: 120...320, step: 5) { "\(Int($0)) pt" }
                SliderRow("Arrondi", value: $settings.expandedCornerRadius, range: 8...48, step: 1) { "\(Int($0)) pt" }
                ToggleRow("Ombre portée", isOn: $settings.showShadow)
            }

            SettingsCard("Animation") {
                SliderRow("Durée", value: $settings.animationResponse, range: 0.15...1, step: 0.01) { String(format: "%.2f s", $0) }
                SliderRow("Rebond", subtitle: "0 = aucun, plus haut = plus élastique.",
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

            NotchShape(topRadius: topRadius,
                       bottomRadius: (expanded ? settings.expandedCornerRadius : NotchViewModel.collapsedBottomRadius) * scale)
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    if expanded {
                        HStack(spacing: 10) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.14))
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
                .help("Rejouer l'animation")

                Picker("", selection: Binding(get: { navigation.previewExpanded }, set: { navigation.previewExpanded = $0 })) {
                    Text("Fermée").tag(false)
                    Text("Ouverte").tag(true)
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

// MARK: - Activités en direct

private struct ActivitiesPage: View {
    @Bindable private var settings = IslandSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PageHeader("Activités en direct",
                       subtitle: "Informations brèves qui apparaissent de part et d'autre de l'encoche, sans l'ouvrir.",
                       systemImage: "bolt.fill", tint: .orange)

            SettingsCard(footer: "Chaque module règle ensuite ses propres activités dans sa page.") {
                ToggleRow("Activités en direct", isOn: $settings.liveActivitiesEnabled)
            }

            SettingsCard("Sources") {
                SettingsRow("Lecture en cours", subtitle: "Pochette et égaliseur pendant la lecture.",
                            icon: ("music.note", .pink)) { EmptyView() }
                SettingsRow("Volume & luminosité", subtitle: "Jauge à chaque changement.",
                            icon: ("speaker.wave.2.fill", .blue)) { EmptyView() }
                SettingsRow("Caméra & micro", subtitle: "Points vert et orange pendant l'utilisation.",
                            icon: ("video.fill", .green)) { EmptyView() }
                SettingsRow("Batterie", subtitle: "Branchement du chargeur, batterie faible.",
                            icon: ("battery.75percent", .green)) { EmptyView() }
                SettingsRow("Calendrier", subtitle: "Rappel avant le début d'un événement.",
                            icon: ("calendar", .red)) { EmptyView() }
            }

            SettingsCard("Essayer", footer: "Regarde l'encoche après avoir cliqué.") {
                SettingsRow("Exemple de charge") {
                    Button("Afficher") { showSample(charging: true) }.disabled(!settings.liveActivitiesEnabled)
                }
                SettingsRow("Exemple de rappel") {
                    Button("Afficher") { showSample(charging: false) }.disabled(!settings.liveActivitiesEnabled)
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
                    Text("Réunion").lineLimit(1)
                }
            } trailing: {
                Text("dans 5 min").foregroundStyle(.orange)
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
                    Text(enabled.wrappedValue ? "Activé" : "Désactivé")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsCard("Disposition") {
                switch module.kind {
                case .widget:
                    PositionRow(module: module, title: "Position sur l'accueil", unit: "de gauche à droite")
                case .page:
                    PositionRow(module: module, title: "Position de l'onglet",
                                unit: "parmi les onglets en haut à gauche de l'île ouverte")
                case .background:
                    SettingsRow("Autour de l'encoche",
                                subtitle: "S'affiche sous forme d'activité en direct, pas dans l'île ouverte.") {
                        Image(systemName: "capsule.fill").foregroundStyle(.secondary)
                    }
                }
            }

            if let settingsView = module.settingsView() {
                SettingsCard("Réglages") { settingsView }
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
        SettingsRow(title, subtitle: position.map { "\($0.index) sur \($0.count), \(unit)" }) {
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
