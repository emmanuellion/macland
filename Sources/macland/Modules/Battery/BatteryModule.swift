import IOKit.ps
import SwiftUI

enum BatteryPlacement: String, CaseIterable, Identifiable {
    /// Petit indicateur en haut à droite de l'île ouverte.
    case corner
    /// Widget de l'accueil.
    case widget

    var id: String { rawValue }

    var label: String {
        switch self {
        case .corner: tr("Coin", "Corner")
        case .widget: tr("Widget", "Widget")
        }
    }
}

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
    var name: String { tr("Batterie", "Battery") }
    let systemImage = "battery.75percent"
    var summary: String { tr("Niveau de batterie, état de charge et autonomie restante.", "Battery level, charging state and time remaining.") }
    let tint = Color.green

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "battery", registering: [
        "showTimeRemaining": true,
        "lowThreshold": 20.0,
        "placement": BatteryPlacement.corner.rawValue,
        "chargingActivity": true,
        "lowBatteryActivity": true,
    ])

    var showTimeRemaining: Bool { didSet { store.set(showTimeRemaining, "showTimeRemaining") } }
    var lowThreshold: Double { didSet { store.set(lowThreshold, "lowThreshold") } }
    var placement: BatteryPlacement { didSet { store.set(placement.rawValue, "placement") } }
    /// Activité en direct au branchement / débranchement du chargeur.
    var chargingActivity: Bool { didSet { store.set(chargingActivity, "chargingActivity") } }
    /// Activité en direct quand la batterie passe sous le seuil.
    var lowBatteryActivity: Bool { didSet { store.set(lowBatteryActivity, "lowBatteryActivity") } }

    private(set) var state = BatteryState()

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    init() {
        showTimeRemaining = store.bool("showTimeRemaining")
        lowThreshold = store.double("lowThreshold")
        placement = BatteryPlacement(rawValue: store.string("placement")) ?? .corner
        chargingActivity = store.bool("chargingActivity")
        lowBatteryActivity = store.bool("lowBatteryActivity")
    }

    func expandedView() -> AnyView { AnyView(BatteryView(module: self)) }

    var isVisibleInHome: Bool { placement == .widget }

    func headerAccessory() -> AnyView? {
        guard placement == .corner, state.hasBattery else { return nil }
        return AnyView(BatteryCorner(module: self))
    }
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
            let color: Color = plugged ? .green : (Double(new.percentage) <= lowThreshold ? .red : Color.primary)
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
                Text(tr("Batterie faible", "Low battery")).foregroundStyle(.red).lineLimit(1).fixedSize()
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
        return Double(state.percentage) <= module.lowThreshold ? .red : Color.primary
    }

    private var subtitle: String? {
        if state.isPluggedIn && !state.isCharging { return tr("Branché", "Plugged in") }
        guard module.showTimeRemaining, let minutes = state.minutesRemaining else {
            return state.isCharging ? tr("En charge", "Charging") : nil
        }
        let time = "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
        return state.isCharging ? tr("Pleine dans \(time)", "Full in \(time)") : tr("\(time) restantes", "\(time) left")
    }

    private func icon(width: CGFloat) -> some View {
        BatteryIcon(percentage: state.percentage, color: tint, isCharging: state.isCharging)
            .frame(width: width, height: width * 0.47)
    }

    private func percentage(size: CGFloat) -> some View {
        Text("\(state.percentage) %")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
    }

    var body: some View {
        if state.hasBattery {
            // Du plus complet au plus compact : l'île garde la première variante qui tient.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    icon(width: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        percentage(size: 20)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    icon(width: 30)
                    percentage(size: 18)
                }
                VStack(spacing: 4) {
                    icon(width: 26)
                    percentage(size: 14).minimumScaleFactor(0.7)
                }
            }
            .lineLimit(1)
        } else {
            Label(tr("Pas de batterie", "No battery"), systemImage: "powerplug")
                .foregroundStyle(.secondary)
        }
    }
}

/// Indicateur compact du coin supérieur droit : pourcentage + petite batterie.
private struct BatteryCorner: View {
    let module: BatteryModule

    var body: some View {
        let state = module.state
        let color: Color = state.isCharging || state.isPluggedIn ? .green
            : Double(state.percentage) <= module.lowThreshold ? .red : Color.primary
        HStack(spacing: 5) {
            Text("\(state.percentage) %")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            BatteryIcon(percentage: state.percentage, color: color, isCharging: state.isCharging)
                .frame(width: 24, height: 11)
        }
        .help(state.isCharging ? tr("En charge", "Charging") : tr("Batterie", "Battery"))
    }
}

/// Batterie dessinée (le symbole système ignore la teinte dans certains rendus).
private struct BatteryIcon: View {
    let percentage: Int
    let color: Color
    let isCharging: Bool

    var body: some View {
        GeometryReader { proxy in
            let capWidth = proxy.size.width * 0.07
            let bodyWidth = proxy.size.width - capWidth - 1.5
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: proxy.size.height * 0.3, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: proxy.size.height * 0.18, style: .continuous)
                        .fill(color)
                        .frame(width: max(2, (bodyWidth - 6) * CGFloat(min(max(percentage, 0), 100)) / 100))
                        .padding(3)
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: proxy.size.height * 0.7, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: bodyWidth)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: capWidth, height: proxy.size.height * 0.4)
            }
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
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
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
        SettingsSubheader(tr("Affichage", "Display"))
        PickerRow(tr("Position", "Position"),
                  subtitle: module.placement == .corner
                      ? tr("Petit indicateur en haut à droite de l'île ouverte.", "Small indicator at the top right of the open island.")
                      : tr("Widget sur l'accueil, à côté des autres.", "Widget on the home page, next to the others."),
                  selection: $module.placement) {
            ForEach(BatteryPlacement.allCases) { Text($0.label).tag($0) }
        }
        ToggleRow(tr("Autonomie restante", "Time remaining"),
                  subtitle: tr("Temps avant la fin de la charge ou de la batterie.", "Time until fully charged or empty."),
                  isOn: $module.showTimeRemaining)
        SettingsSubheader(tr("Alertes", "Alerts"))
        SliderRow(tr("Seuil batterie faible", "Low battery threshold"), value: $module.lowThreshold, range: 5...50, step: 5) { "\(Int($0)) %" }
        ToggleRow(tr("Alerte batterie faible", "Low battery alert"),
                  subtitle: tr("Prévient quand le niveau passe sous le seuil.", "Warns when the level drops below the threshold."),
                  isOn: $module.lowBatteryActivity)
        ToggleRow(tr("Activité au branchement", "Charger activity"),
                  subtitle: tr("Affiche le niveau quand tu branches ou débranches le chargeur.",
                               "Shows the level when you plug in or unplug the charger."),
                  isOn: $module.chargingActivity)
    }
}
