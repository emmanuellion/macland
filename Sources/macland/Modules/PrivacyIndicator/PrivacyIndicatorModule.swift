import SwiftUI

@MainActor
@Observable
final class PrivacyIndicatorModule: IslandModule {
    let id = "privacy"
    var name: String { tr("Caméra & micro", "Camera & Mic") }
    let systemImage = "video.fill"
    var summary: String {
        tr("Signale à côté de l'encoche quand une app utilise la caméra ou le micro.",
           "Shows next to the notch when an app is using the camera or microphone.")
    }
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
                announceUse(tr("Caméra", "Camera"), systemImage: "video.fill", color: Self.cameraColor, apps: [])
            } else if let newApp = microphone.first(where: { !microphoneApps.contains($0) }) {
                announceUse(tr("Micro", "Mic"), systemImage: "mic.fill", color: Self.microphoneColor, apps: [newApp])
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
            Text(apps.first ?? tr("active", "active"))
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
        if module.cameraActive { parts.append(tr("caméra active", "camera in use")) }
        if !module.microphoneApps.isEmpty { parts.append(tr("micro : ", "mic: ") + module.microphoneApps.joined(separator: ", ")) }
        return parts.isEmpty ? tr("Rien n'utilise la caméra ni le micro.", "Nothing is using the camera or microphone.") : parts.joined(separator: " · ").capitalizingFirstLetter
    }

    var body: some View {
        SettingsSubheader(tr("Surveillance", "Monitoring"))
        SettingsRow(tr("En ce moment", "Right now"), subtitle: status) {
            HStack(spacing: 6) {
                Circle().fill(module.cameraActive ? PrivacyIndicatorModule.cameraColor : .secondary.opacity(0.3))
                    .frame(width: 9, height: 9)
                Circle().fill(module.microphoneApps.isEmpty ? .secondary.opacity(0.3) : PrivacyIndicatorModule.microphoneColor)
                    .frame(width: 9, height: 9)
            }
        }
        ToggleRow(tr("Caméra", "Camera"), subtitle: tr("Point vert à gauche de l'encoche.", "Green dot to the left of the notch."), leadingColor: PrivacyIndicatorModule.cameraColor,
                  isOn: $module.watchesCamera)
        ToggleRow(tr("Micro", "Microphone"), subtitle: tr("Point orange à droite de l'encoche.", "Orange dot to the right of the notch."), leadingColor: PrivacyIndicatorModule.microphoneColor,
                  isOn: $module.watchesMicrophone)
        SettingsSubheader(tr("Affichage", "Display"))
        ToggleRow(tr("Points persistants", "Persistent dots"),
                  subtitle: tr("Restent affichés tant que la caméra ou le micro sont utilisés.",
                               "Stay visible while the camera or microphone is in use."),
                  isOn: $module.persistentDots)
        ToggleRow(tr("Annonce au démarrage", "Announce on start"),
                  subtitle: tr("Affiche brièvement quelle app commence à utiliser le micro.",
                               "Briefly shows which app starts using the microphone."),
                  isOn: $module.announce)
    }
}
