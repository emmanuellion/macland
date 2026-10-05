import SwiftUI

/// État de l'écran d'accueil (pas de `@State` : macro indisponible sans Xcode).
@MainActor
@Observable
final class OnboardingState {
    static let pageCount = 4
    var page = 0
}

/// Écran d'accueil du premier lancement : présentation, choix des modules, permissions, astuces.
struct OnboardingView: View {
    let state: OnboardingState
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.page {
                case 0: WelcomePage()
                case 1: ModulesPage()
                case 2: PermissionsPage()
                default: ReadyPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 48)
            .id(state.page)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity))

            footer
        }
        .frame(width: 760, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, IslandSettings.shared.locale)
    }

    private var footer: some View {
        HStack {
            // Masqué (mais gardé) sur la dernière page pour que les points restent centrés.
            Button(tr("Passer", "Skip"), action: onFinish)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(state.page < OnboardingState.pageCount - 1 ? 1 : 0)
                .disabled(state.page == OnboardingState.pageCount - 1)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<OnboardingState.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == state.page ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: index == state.page ? 18 : 7, height: 7)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                if state.page > 0 {
                    Button(tr("Retour", "Back")) { withAnimation(.smooth) { state.page -= 1 } }
                }
                if state.page < OnboardingState.pageCount - 1 {
                    Button(tr("Continuer", "Continue")) { withAnimation(.smooth) { state.page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(tr("Commencer", "Get started"), action: onFinish)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
    }
}

// MARK: - Pages

private struct PageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520)
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .purple.opacity(0.3), radius: 18, y: 8)
            PageTitle(title: tr("Bienvenue dans macland", "Welcome to macland"),
                      subtitle: tr("L'encoche de ton MacBook devient une île vivante : musique, fichiers, presse-papiers, réglages rapides… Tout se configure, et rien ne quitte ton Mac (sauf la météo, si tu l'actives).",
                                   "Your MacBook's notch becomes a living island: music, files, clipboard, quick controls… Everything is configurable, and nothing leaves your Mac (except weather, if you turn it on)."))
            Label(tr("Passe la souris sur l'encoche pour ouvrir l'île.", "Hover the notch to open the island."),
                  systemImage: "cursorarrow.motionlines")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            Spacer(minLength: 0)
        }
    }
}

private struct ModulesPage: View {
    private let registry = ModuleRegistry.shared

    var body: some View {
        VStack(spacing: 24) {
            PageTitle(title: tr("Choisis tes modules", "Pick your modules"),
                      subtitle: tr("Active ce qui t'intéresse. Tu pourras tout changer plus tard dans les réglages.",
                                   "Turn on what you like. You can change everything later in Settings."))
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(registry.orderedModules, id: \.id) { module in
                        ModuleCard(module: module)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct ModuleCard: View {
    let module: any IslandModule
    private let registry = ModuleRegistry.shared

    var body: some View {
        let enabled = registry.isEnabled(module)
        Button {
            registry.setEnabled(!enabled, for: module)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemImage: module.systemImage, tint: module.tint, size: 32)
                    .saturation(enabled ? 1 : 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(module.name).font(.system(size: 13, weight: .semibold))
                    Text(module.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(enabled ? Color.accentColor : Color.primary.opacity(0.25))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(enabled ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: enabled ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionsPage: View {
    private let registry = ModuleRegistry.shared

    var body: some View {
        VStack(spacing: 24) {
            PageTitle(title: tr("Autorisations", "Permissions"),
                      subtitle: tr("Toutes sont facultatives : sans elles, macland fonctionne, avec un peu moins de fonctions.",
                                   "All optional: macland works without them, with a few features fewer."))

            // Les statuts sont relus chaque seconde tant que la page est affichée.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 12) {
                    PermissionRow(systemImage: "hand.raised.fill", tint: .blue,
                                  title: tr("Accessibilité", "Accessibility"),
                                  detail: tr("Remplacer le HUD volume / luminosité de macOS et coller automatiquement depuis le presse-papiers.",
                                             "Replace the macOS volume / brightness HUD and auto-paste from the clipboard."),
                                  isGranted: AXIsProcessTrusted()) {
                        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                    if let calendar = registry.module(id: "calendar") as? CalendarModule, registry.isEnabled(calendar) {
                        PermissionRow(systemImage: "calendar", tint: .red,
                                      title: tr("Calendrier", "Calendar"),
                                      detail: tr("Afficher tes prochains événements et te les rappeler.",
                                                 "Show your upcoming events and remind you of them."),
                                      isGranted: calendar.access == .granted) {
                            if calendar.access == .denied {
                                calendar.openPrivacySettings()
                            } else {
                                Task { await calendar.requestAccess() }
                            }
                        }
                    }
                }
                .frame(maxWidth: 560)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PermissionRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImage, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if isGranted {
                Label(tr("Autorisé", "Allowed"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button(tr("Autoriser", "Allow"), action: request)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        )
    }
}

private struct ReadyPage: View {
    @Bindable private var launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        VStack(spacing: 26) {
            PageTitle(title: tr("C'est prêt !", "You're all set!"),
                      subtitle: tr("Quelques gestes à connaître :", "A few things to know:"))
            VStack(alignment: .leading, spacing: 14) {
                Tip(systemImage: "cursorarrow.rays", text: tr("Survole l'encoche pour ouvrir l'île.", "Hover the notch to open the island."))
                Tip(systemImage: "doc.on.clipboard", text: tr("⌃⌘V ouvre l'historique du presse-papiers, n'importe où.",
                                                              "⌃⌘V opens the clipboard history from anywhere."))
                Tip(systemImage: "tray.and.arrow.down", text: tr("Glisse un fichier sur l'encoche pour le garder dans l'étagère.",
                                                                 "Drag a file onto the notch to keep it on the shelf."))
                Tip(systemImage: "gearshape", text: tr("Clic droit sur l'île, ou l'icône de la barre des menus, pour les réglages.",
                                                       "Right-click the island, or use the menu bar icon, for Settings."))
            }
            .frame(maxWidth: 480, alignment: .leading)

            Toggle(tr("Lancer macland à l'ouverture de session", "Launch macland at login"), isOn: $launchAtLogin.isEnabled)
                .toggleStyle(.switch)
            if let error = launchAtLogin.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Tip: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            Text(text).font(.system(size: 13.5))
        }
    }
}
