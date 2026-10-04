import AppKit
import SwiftUI

enum HUDMode: String, CaseIterable, Identifiable {
    /// Intercepte les touches et masque le HUD d'Apple (permission Accessibilité).
    case replace
    /// Réagit aux changements sans toucher aux touches : le HUD d'Apple s'affiche aussi.
    case alongside

    var id: String { rawValue }

    var label: String {
        switch self {
        case .replace: tr("Remplacer", "Replace")
        case .alongside: tr("En plus", "Alongside")
        }
    }
}

enum HUDStyle: String, CaseIterable, Identifiable {
    /// Icône et jauge de part et d'autre de l'encoche.
    case compact
    /// Barre sous l'encoche, qu'on peut faire glisser.
    case extended

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: tr("Compact", "Compact")
        case .extended: tr("Étendu", "Extended")
        }
    }
}

enum HUDKind {
    case volume, brightness
}

@MainActor
@Observable
final class SystemHUDModule: IslandModule {
    let id = "hud"
    var name: String { tr("Volume & luminosité", "Volume & Brightness") }
    let systemImage = "speaker.wave.2.fill"
    var summary: String {
        tr("Remplace les fenêtres de volume et de luminosité de macOS par une jauge dans l'encoche.",
           "Replaces the macOS volume and brightness overlays with a gauge in the notch.")
    }
    let tint = Color.blue
    let kind = ModuleKind.background

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "hud", registering: [
        "mode": HUDMode.replace.rawValue,
        "style": HUDStyle.extended.rawValue,
        "volume": true,
        "brightness": true,
        "duration": 1.6,
        "showPercentage": true,
        "fineSteps": false,
    ])

    var mode: HUDMode { didSet { store.set(mode.rawValue, "mode"); restart() } }
    var style: HUDStyle { didSet { store.set(style.rawValue, "style") } }
    var handlesVolume: Bool { didSet { store.set(handlesVolume, "volume"); restart() } }
    var handlesBrightness: Bool { didSet { store.set(handlesBrightness, "brightness"); restart() } }
    var duration: Double { didSet { store.set(duration, "duration") } }
    var showPercentage: Bool { didSet { store.set(showPercentage, "showPercentage") } }
    /// Pas de 1/32 au lieu de 1/16 (comme ⌥⇧ + touche dans macOS).
    var fineSteps: Bool { didSet { store.set(fineSteps, "fineSteps") } }

    private(set) var hasAccessibility = AXIsProcessTrusted()
    /// Le raccourci n'a pas pu être installé alors que la permission semble accordée.
    private(set) var tapFailed = false

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var keyTap: MediaKeyTap?
    @ObservationIgnored private var outputObserver: AnyObject?
    @ObservationIgnored private var brightnessTimer: Timer?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var lastBrightness: Float?
    @ObservationIgnored private var lastVolume: (Float?, Bool)?

    init() {
        mode = HUDMode(rawValue: store.string("mode")) ?? .replace
        style = HUDStyle(rawValue: store.string("style")) ?? .extended
        handlesVolume = store.bool("volume")
        handlesBrightness = store.bool("brightness")
        duration = store.double("duration")
        showPercentage = store.bool("showPercentage")
        fineSteps = store.bool("fineSteps")
    }

    func expandedView() -> AnyView { AnyView(EmptyView()) }
    func settingsView() -> AnyView? { AnyView(SystemHUDSettingsView(module: self)) }

    func start() {
        isRunning = true
        lastVolume = (AudioDevices.volume, AudioDevices.isMuted)
        lastBrightness = DisplayBrightness.value

        if handlesVolume {
            // Affiche le HUD à chaque changement de volume, d'où qu'il vienne (touches, réglages, autre app).
            outputObserver = AudioDevices.observeOutput { [weak self] in self?.volumeDidChange() }
        }

        if mode == .replace { installKeyTap() }
        updateBrightnessPolling()
    }

    /// Sans interception des touches, pas d'événement public pour la luminosité : on la surveille.
    private func updateBrightnessPolling() {
        let needsPolling = isRunning && handlesBrightness && keyTap == nil
        if needsPolling, brightnessTimer == nil {
            brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollBrightness() }
            }
        } else if !needsPolling {
            brightnessTimer?.invalidate()
            brightnessTimer = nil
        }
    }

    func stop() {
        isRunning = false
        keyTap = nil
        outputObserver = nil
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        ActivityCenter.shared.dismiss("hud")
    }

    private func restart() {
        guard isRunning else { return }
        stop()
        start()
    }

    // MARK: Touches

    private func installKeyTap() {
        hasAccessibility = AXIsProcessTrusted()
        guard hasAccessibility else {
            // On réessaie dès que l'utilisateur accorde la permission.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, AXIsProcessTrusted() else { return }
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.installKeyTap()
                }
            }
            return
        }
        keyTap = MediaKeyTap { [weak self] key, _, modifiers in
            self?.handle(key, modifiers: modifiers) ?? false
        }
        tapFailed = keyTap == nil
        updateBrightnessPolling()
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Renvoie `true` si la touche est prise en charge (l'événement est alors retiré, plus de HUD Apple).
    private func handle(_ key: MediaKey, modifiers: NSEvent.ModifierFlags) -> Bool {
        // ⌥ + touche ouvre les réglages système correspondants : on laisse faire macOS.
        if modifiers.contains(.option) && !modifiers.contains(.shift) { return false }
        let step: Float = (fineSteps || modifiers.contains([.option, .shift])) ? 1 / 32 : 1 / 16

        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard handlesVolume, AudioDevices.canSetVolume else { return false }
            if key == .mute {
                AudioDevices.setMuted(!AudioDevices.isMuted)
            } else {
                let current = AudioDevices.volume ?? 0
                let target = key == .volumeUp ? current + step : current - step
                AudioDevices.setVolume((target / step).rounded() * step)
                if key == .volumeUp, AudioDevices.isMuted { AudioDevices.setMuted(false) }
            }
            showHUD(.volume)
            return true
        case .brightnessUp, .brightnessDown:
            guard handlesBrightness, DisplayBrightness.isAvailable else { return false }
            let current = DisplayBrightness.value ?? 0.5
            let target = key == .brightnessUp ? current + step : current - step
            DisplayBrightness.set((target / step).rounded() * step)
            lastBrightness = DisplayBrightness.value
            showHUD(.brightness)
            return true
        }
    }

    // MARK: Changements

    private func volumeDidChange() {
        let current = (AudioDevices.volume, AudioDevices.isMuted)
        defer { lastVolume = current }
        // Changement de sortie sans changement de volume : rien à afficher.
        if let last = lastVolume, last.0 == current.0, last.1 == current.1 { return }
        showHUD(.volume)
    }

    private func pollBrightness() {
        guard let value = DisplayBrightness.value else { return }
        defer { lastBrightness = value }
        if let last = lastBrightness, abs(last - value) > 0.001 { showHUD(.brightness) }
    }

    // MARK: Affichage

    func showHUD(_ kind: HUDKind) {
        let value: Double
        let symbol: String
        let muted = kind == .volume && AudioDevices.isMuted
        switch kind {
        case .volume:
            value = muted ? 0 : Double(AudioDevices.volume ?? 0)
            symbol = muted || value == 0 ? "speaker.slash.fill"
                : value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness:
            value = Double(DisplayBrightness.value ?? 0)
            symbol = value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }

        let label = Text("\(Int((value * 100).rounded())) %").monospacedDigit()
        let percentage = showPercentage
        let icon = Image(systemName: symbol)
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(muted ? Color.primary.opacity(0.5) : Color.primary)

        let activity: LiveActivity
        switch style {
        case .compact:
            activity = LiveActivity(id: "hud", priority: 5, duration: duration, sideWidth: 74) {
                icon
            } trailing: {
                HStack(spacing: 6) {
                    HUDBar(value: value, dimmed: muted).frame(width: percentage ? 34 : 56, height: 5)
                    if percentage { label.font(.system(size: 11, weight: .semibold)) }
                }
            }
        case .extended:
            activity = LiveActivity(id: "hud", priority: 5, duration: duration, sideWidth: 40, bottomHeight: 30,
                                    isInteractive: true) {
                icon
            } trailing: {
                if percentage { label.font(.system(size: 11, weight: .semibold)) }
            } bottom: {
                HUDSlider(value: value, dimmed: muted) { [weak self] newValue in
                    self?.set(kind, to: newValue)
                }
            }
        }
        ActivityCenter.shared.show(activity)
    }

    private func set(_ kind: HUDKind, to value: Double) {
        switch kind {
        case .volume:
            AudioDevices.setVolume(Float(value))
        case .brightness:
            DisplayBrightness.set(Float(value))
            lastBrightness = DisplayBrightness.value
        }
        showHUD(kind)
    }
}

// MARK: - Vues

private struct HUDBar: View {
    let value: Double
    let dimmed: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.2))
                Capsule()
                    .fill(Color.primary.opacity(dimmed ? 0.4 : 1))
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .animation(.smooth(duration: 0.12), value: value)
    }
}

/// Jauge du style étendu : on peut cliquer ou glisser dessus pour régler.
private struct HUDSlider: View {
    let value: Double
    let dimmed: Bool
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            HUDBar(value: value, dimmed: dimmed)
                .frame(height: 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    onChange(min(max(drag.location.x / proxy.size.width, 0), 1))
                })
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Réglages

private struct SystemHUDSettingsView: View {
    @Bindable var module: SystemHUDModule

    var body: some View {
        PickerRow(tr("Mode", "Mode"),
                  subtitle: module.mode == .replace
                      ? tr("Intercepte les touches : seul le HUD d'Island s'affiche.",
                           "Intercepts the keys: only Island's HUD is shown.")
                      : tr("Sans permission : le HUD de macOS s'affiche aussi.",
                           "No permission needed: the macOS HUD is shown too."),
                  selection: $module.mode) {
            ForEach(HUDMode.allCases) { Text($0.label).tag($0) }
        }
        if module.mode == .replace && !module.hasAccessibility {
            SettingsRow(tr("Permission Accessibilité requise", "Accessibility permission required"),
                        subtitle: tr("Nécessaire pour intercepter les touches volume et luminosité.",
                                     "Needed to intercept the volume and brightness keys.")) {
                HStack {
                    Button(tr("Autoriser", "Allow")) { module.requestAccessibility() }
                    Button(tr("Réglages", "Settings")) { module.openAccessibilitySettings() }
                }
            }
        } else if module.mode == .replace && module.tapFailed {
            SettingsRow(tr("Interception impossible", "Can't intercept keys"),
                        subtitle: tr("Retire puis rajoute Island dans Confidentialité › Accessibilité.",
                                     "Remove and re-add Island in Privacy › Accessibility.")) {
                Button(tr("Réglages", "Settings")) { module.openAccessibilitySettings() }
            }
        }
        PickerRow(tr("Style", "Style"), subtitle: module.style == .extended
                      ? tr("Barre sous l'encoche, réglable à la souris.", "Bar below the notch, adjustable with the mouse.")
                      : tr("Icône et jauge de part et d'autre de l'encoche.", "Icon and gauge on either side of the notch."),
                  selection: $module.style) {
            ForEach(HUDStyle.allCases) { Text($0.label).tag($0) }
        }
        ToggleRow(tr("Volume", "Volume"), isOn: $module.handlesVolume)
        ToggleRow(tr("Luminosité", "Brightness"),
                  subtitle: DisplayBrightness.isAvailable ? nil : tr("Indisponible sur cet écran.", "Not available on this display."),
                  isOn: $module.handlesBrightness)
        ToggleRow(tr("Pourcentage", "Percentage"), isOn: $module.showPercentage)
        ToggleRow(tr("Pas fins", "Fine steps"),
                  subtitle: tr("Réglage par 1/32 au lieu de 1/16 (mode Remplacer).", "Adjust in 1/32 steps instead of 1/16 (Replace mode)."),
                  isOn: $module.fineSteps)
        SliderRow(tr("Durée d'affichage", "Display duration"), value: $module.duration, range: 0.8...4, step: 0.1) { String(format: "%.1f s", $0) }
        SettingsRow(tr("Essayer", "Try it")) {
            HStack {
                Button(tr("Volume", "Volume")) { module.showHUD(.volume) }
                Button(tr("Luminosité", "Brightness")) { module.showHUD(.brightness) }
            }
        }
    }
}
