import IOKit.ps
import SwiftUI

struct BatteryState: Equatable {
    var percentage: Int = 0
    var isCharging = false
    var isPluggedIn = false
    /// Minutes restantes (décharge) ou avant charge complète (charge). `nil` si inconnu.
    var minutesRemaining: Int?
    var hasBattery = false
}

@MainActor
@Observable
final class BatteryModule: IslandModule {
    let id = "battery"
    let name = "Batterie"
    let systemImage = "battery.75percent"
    let summary = "Niveau de batterie, état de charge et autonomie restante."
    let tint = Color.green

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "battery", registering: [
        "showTimeRemaining": true,
        "lowThreshold": 20.0,
        "chargingActivity": true,
        "lowBatteryActivity": true,
    ])

    var showTimeRemaining: Bool { didSet { store.set(showTimeRemaining, "showTimeRemaining") } }
    var lowThreshold: Double { didSet { store.set(lowThreshold, "lowThreshold") } }
    /// Activité en direct au branchement / débranchement du chargeur.
    var chargingActivity: Bool { didSet { store.set(chargingActivity, "chargingActivity") } }
    /// Activité en direct quand la batterie passe sous le seuil.
    var lowBatteryActivity: Bool { didSet { store.set(lowBatteryActivity, "lowBatteryActivity") } }

    private(set) var state = BatteryState()

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    init() {
        showTimeRemaining = store.bool("showTimeRemaining")
        lowThreshold = store.double("lowThreshold")
        chargingActivity = store.bool("chargingActivity")
        lowBatteryActivity = store.bool("lowBatteryActivity")
    }

    func expandedView() -> AnyView { AnyView(BatteryView(module: self)) }
    func settingsView() -> AnyView? { AnyView(BatterySettingsView(module: self)) }

    func start() {
        refresh()
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let module = Unmanaged<BatteryModule>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { module.refresh() }
        }, context)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    private func announceChanges(from old: BatteryState, to new: BatteryState) {
        if chargingActivity, old.isPluggedIn != new.isPluggedIn {
            let plugged = new.isPluggedIn
            let color: Color = plugged ? .green : (Double(new.percentage) <= lowThreshold ? .red : .white)
            ActivityCenter.shared.show(LiveActivity(id: "battery.power", priority: 1) {
                Image(systemName: plugged ? "bolt.fill" : "powerplug")
                    .foregroundStyle(color)
            } trailing: {
                BatteryGauge(percentage: new.percentage, color: color)
            })
        }

        let threshold = Int(lowThreshold)
        if lowBatteryActivity, !new.isPluggedIn, old.percentage > threshold, new.percentage <= threshold {
            ActivityCenter.shared.show(LiveActivity(id: "battery.low", priority: 3, duration: 6) {
                Text("Batterie faible").foregroundStyle(.red).lineLimit(1).fixedSize()
            } trailing: {
                BatteryGauge(percentage: new.percentage, color: .red)
            })
        }
    }

    func stop() {
        ActivityCenter.shared.dismiss("battery.power")
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = desc[minutesKey] as? Int

            let newState = BatteryState(
                percentage: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0,
                isCharging: charging,
                isPluggedIn: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil,
                hasBattery: true
            )
            let previous = state
            state = newState
            if previous.hasBattery { announceChanges(from: previous, to: newState) }
            return
        }
        state = BatteryState()
    }
}

private struct BatteryView: View {
    let module: BatteryModule

    private var state: BatteryState { module.state }

    private var tint: Color {
        if state.isCharging || state.isPluggedIn { return .green }
        return Double(state.percentage) <= module.lowThreshold ? .red : .white
    }

    private var symbol: String {
        if state.isCharging { return "battery.100percent.bolt" }
        switch state.percentage {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var subtitle: String? {
        if state.isPluggedIn && !state.isCharging { return "Branché" }
        guard module.showTimeRemaining, let minutes = state.minutesRemaining else {
            return state.isCharging ? "En charge" : nil
        }
        let time = "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
        return state.isCharging ? "Pleine dans \(time)" : "\(time) restantes"
    }

    var body: some View {
        if state.hasBattery {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.percentage) %")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Label("Pas de batterie", systemImage: "powerplug")
                .foregroundStyle(.secondary)
        }
    }
}

/// Pourcentage + petite jauge, pour les activités en direct.
private struct BatteryGauge: View {
    let percentage: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text("\(percentage) %").monospacedDigit()
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: max(2, 18 * CGFloat(percentage) / 100))
                    .padding(2)
            }
            .frame(width: 24, height: 12)
        }
        .foregroundStyle(color)
    }
}

private struct BatterySettingsView: View {
    @Bindable var module: BatteryModule

    var body: some View {
        ToggleRow("Autonomie restante", subtitle: "Temps avant la fin de la charge ou de la batterie.",
                  isOn: $module.showTimeRemaining)
        SliderRow("Seuil batterie faible", value: $module.lowThreshold, range: 5...50, step: 5) { "\(Int($0)) %" }
        ToggleRow("Activité au branchement", subtitle: "Affiche le niveau quand tu branches ou débranches le chargeur.",
                  isOn: $module.chargingActivity)
        ToggleRow("Alerte batterie faible", subtitle: "Prévient quand le niveau passe sous le seuil.",
                  isOn: $module.lowBatteryActivity)
    }
}
