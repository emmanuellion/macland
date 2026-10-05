import SwiftUI

/// Page de réglages rapides façon Centre de contrôle : volume, luminosité de l'écran et du clavier.
@MainActor
@Observable
final class ControlsModule: IslandModule {
    let id = "controls"
    var name: String { tr("Contrôles", "Controls") }
    let systemImage = "slider.horizontal.3"
    var summary: String {
        tr("Volume, luminosité de l'écran et du clavier, réglables directement dans l'île.",
           "Volume, display and keyboard brightness, adjustable right in the island.")
    }
    let tint = Color.gray
    let kind = ModuleKind.page

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "controls", registering: [
        "volume": true,
        "display": true,
        "keyboard": true,
    ])

    var showsVolume: Bool { didSet { store.set(showsVolume, "volume") } }
    var showsDisplay: Bool { didSet { store.set(showsDisplay, "display") } }
    var showsKeyboard: Bool { didSet { store.set(showsKeyboard, "keyboard") } }

    private(set) var volume: Double = 0
    private(set) var isMuted = false
    private(set) var displayBrightness: Double = 0
    private(set) var keyboardBrightness: Double = 0

    @ObservationIgnored private var timer: Timer?

    init() {
        showsVolume = store.bool("volume")
        showsDisplay = store.bool("display")
        showsKeyboard = store.bool("keyboard")
    }

    func expandedView() -> AnyView { AnyView(ControlsView(module: self)) }
    func settingsView() -> AnyView? { AnyView(ControlsSettingsView(module: self)) }

    func stop() { endRefreshing() }

    /// Les valeurs peuvent changer ailleurs (touches, réglages) : on les relit tant que la page est visible.
    func beginRefreshing() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func endRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        volume = Double(AudioDevices.volume ?? 0)
        isMuted = AudioDevices.isMuted
        displayBrightness = Double(DisplayBrightness.value ?? 0)
        keyboardBrightness = Double(KeyboardBrightness.value ?? 0)
    }

    func setVolume(_ value: Double) {
        SystemHUDModule.noteInAppChange()
        AudioDevices.setVolume(Float(value))
        volume = value
        isMuted = AudioDevices.isMuted
    }

    func toggleMute() {
        SystemHUDModule.noteInAppChange()
        AudioDevices.setMuted(!isMuted)
        isMuted.toggle()
    }

    func setDisplayBrightness(_ value: Double) {
        SystemHUDModule.noteInAppChange()
        DisplayBrightness.set(Float(value))
        displayBrightness = value
    }

    func setKeyboardBrightness(_ value: Double) {
        SystemHUDModule.noteInAppChange()
        KeyboardBrightness.set(Float(value))
        keyboardBrightness = value
    }
}

// MARK: - Vue

private struct ControlsView: View {
    let module: ControlsModule

    var body: some View {
        VStack(spacing: 10) {
            if module.showsVolume, AudioDevices.canSetVolume {
                HStack(spacing: 8) {
                    CapsuleSlider(value: module.isMuted ? 0 : module.volume,
                                  systemImage: volumeSymbol) { module.setVolume($0) }
                    RoundButton(systemImage: module.isMuted ? "speaker.slash.fill" : "speaker.fill",
                                isActive: module.isMuted) { module.toggleMute() }
                }
            }
            if module.showsDisplay, DisplayBrightness.isAvailable {
                CapsuleSlider(value: module.displayBrightness, systemImage: "sun.max.fill") {
                    module.setDisplayBrightness($0)
                }
            }
            if module.showsKeyboard, KeyboardBrightness.isAvailable {
                CapsuleSlider(value: module.keyboardBrightness, systemImage: "light.max") {
                    module.setKeyboardBrightness($0)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { module.beginRefreshing() }
        .onDisappear { module.endRefreshing() }
    }

    private var volumeSymbol: String {
        if module.isMuted || module.volume == 0 { return "speaker.slash.fill" }
        return module.volume < 0.34 ? "speaker.wave.1.fill" : module.volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// Curseur épais façon Centre de contrôle : on clique ou glisse n'importe où dessus.
private struct CapsuleSlider: View {
    let value: Double
    let systemImage: String
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Rectangle()
                    .fill(IslandSettings.shared.islandAccent == .neutral
                          ? Color.primary.opacity(0.85) : IslandSettings.shared.islandAccent.color)
                    .frame(width: width * min(max(value, 0), 1))
                // L'icône s'inverse quand le remplissage passe dessous.
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(value > 0.08 ? AnyShapeStyle(.background) : AnyShapeStyle(Color.primary.opacity(0.6)))
                    .padding(.leading, 12)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(max(drag.location.x / width, 0), 1))
            })
        }
        .frame(height: 28)
        .animation(.smooth(duration: 0.1), value: value)
    }
}

private struct RoundButton: View {
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.background) : AnyShapeStyle(Color.primary))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(isActive ? 0.85 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Réglages

private struct ControlsSettingsView: View {
    @Bindable var module: ControlsModule

    var body: some View {
        ToggleRow(tr("Volume", "Volume"), subtitle: AudioDevices.canSetVolume ? nil
                      : tr("La sortie actuelle n'a pas de volume réglable.", "The current output has no adjustable volume."),
                  isOn: $module.showsVolume)
        ToggleRow(tr("Luminosité de l'écran", "Display brightness"),
                  subtitle: DisplayBrightness.isAvailable ? nil : tr("Indisponible sur cet écran.", "Not available on this display."),
                  isOn: $module.showsDisplay)
        ToggleRow(tr("Luminosité du clavier", "Keyboard brightness"),
                  subtitle: KeyboardBrightness.isAvailable ? nil : tr("Pas de clavier rétroéclairé détecté.", "No backlit keyboard detected."),
                  isOn: $module.showsKeyboard)
    }
}
