import SwiftUI

@MainActor
@Observable
final class PrivacyIndicatorModule: IslandModule {
    let id = "privacy"
    let name = "Caméra & micro"
    let systemImage = "video.fill"
    let summary = "Signale à côté de l'encoche quand une app utilise la caméra ou le micro."
    let tint = Color.green
    let kind = ModuleKind.background

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "privacy", registering: [
        "camera": true,
        "microphone": true,
        "announce": true,
        "persistentDots": true,
    ])

    var watchesCamera: Bool { didSet { store.set(watchesCamera, "camera"); refresh() } }
    var watchesMicrophone: Bool { didSet { store.set(watchesMicrophone, "microphone"); refresh() } }
    /// Activité brève au début de l'utilisation (« Caméra · FaceTime »).
    var announce: Bool { didSet { store.set(announce, "announce") } }
    /// Points de couleur tant que la caméra / le micro restent actifs.
    var persistentDots: Bool { didSet { store.set(persistentDots, "persistentDots"); refresh() } }

    private(set) var cameraActive = false
    private(set) var microphoneApps: [String] = []

    @ObservationIgnored private var timer: Timer?

    static let cameraColor = Color.green
    static let microphoneColor = Color.orange

    init() {
        watchesCamera = store.bool("camera")
        watchesMicrophone = store.bool("microphone")
        announce = store.bool("announce")
        persistentDots = store.bool("persistentDots")
    }

    func expandedView() -> AnyView { AnyView(EmptyView()) }
    func settingsView() -> AnyView? { AnyView(PrivacySettingsView(module: self)) }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cameraActive = false
        microphoneApps = []
        ActivityCenter.shared.dismiss("privacy")
        ActivityCenter.shared.dismiss("privacy.announce")
    }

    private func refresh() {
        guard timer != nil || cameraActive || !microphoneApps.isEmpty else { return }
        let camera = watchesCamera && CameraUsage.isAnyCameraRunning
        let microphone = watchesMicrophone ? AudioDevices.appsUsingMicrophone : []

        if announce {
            if camera && !cameraActive {
                announceUse("Caméra", systemImage: "video.fill", color: Self.cameraColor, apps: [])
            } else if let newApp = microphone.first(where: { !microphoneApps.contains($0) }) {
                announceUse("Micro", systemImage: "mic.fill", color: Self.microphoneColor, apps: [newApp])
            }
        }

        cameraActive = camera
        microphoneApps = microphone
        updateDots()
    }

    private func announceUse(_ label: String, systemImage: String, color: Color, apps: [String]) {
        ActivityCenter.shared.show(LiveActivity(id: "privacy.announce", priority: 4, duration: 3) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).foregroundStyle(color)
                Text(label).lineLimit(1).fixedSize()
            }
        } trailing: {
            Text(apps.first ?? "active")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        })
    }

    private func updateDots() {
        guard persistentDots, cameraActive || !microphoneApps.isEmpty else {
            ActivityCenter.shared.dismiss("privacy")
            return
        }
        let camera = cameraActive
        let microphone = !microphoneApps.isEmpty
        // Au-dessus de la lecture en cours : pendant un appel, c'est l'information importante.
        ActivityCenter.shared.show(LiveActivity(id: "privacy", priority: 0, duration: nil, sideWidth: 16) {
            if camera { Circle().fill(Self.cameraColor).frame(width: 7, height: 7) }
        } trailing: {
            if microphone { Circle().fill(Self.microphoneColor).frame(width: 7, height: 7) }
        })
    }
}

// MARK: - Réglages

private struct PrivacySettingsView: View {
    @Bindable var module: PrivacyIndicatorModule

    private var status: String {
        var parts: [String] = []
        if module.cameraActive { parts.append("caméra active") }
        if !module.microphoneApps.isEmpty { parts.append("micro : " + module.microphoneApps.joined(separator: ", ")) }
        return parts.isEmpty ? "Rien n'utilise la caméra ni le micro." : parts.joined(separator: " · ").capitalizingFirstLetter
    }

    var body: some View {
        SettingsRow("En ce moment", subtitle: status) {
            HStack(spacing: 6) {
                Circle().fill(module.cameraActive ? PrivacyIndicatorModule.cameraColor : .secondary.opacity(0.3))
                    .frame(width: 9, height: 9)
                Circle().fill(module.microphoneApps.isEmpty ? .secondary.opacity(0.3) : PrivacyIndicatorModule.microphoneColor)
                    .frame(width: 9, height: 9)
            }
        }
        ToggleRow("Caméra", subtitle: "Point vert à gauche de l'encoche.", leadingColor: PrivacyIndicatorModule.cameraColor,
                  isOn: $module.watchesCamera)
        ToggleRow("Micro", subtitle: "Point orange à droite de l'encoche.", leadingColor: PrivacyIndicatorModule.microphoneColor,
                  isOn: $module.watchesMicrophone)
        ToggleRow("Annonce au démarrage", subtitle: "Affiche brièvement quelle app commence à utiliser le micro.",
                  isOn: $module.announce)
        ToggleRow("Points persistants", subtitle: "Restent affichés tant que la caméra ou le micro sont utilisés.",
                  isOn: $module.persistentDots)
    }
}
