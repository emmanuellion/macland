import SwiftUI

@MainActor
@Observable
final class ClockModule: IslandModule {
    let id = "clock"
    var name: String { tr("Date & heure", "Date & Time") }
    let systemImage = "clock"
    var summary: String { tr("Affiche l'heure et la date du jour.", "Shows the current time and date.") }
    let tint = Color.gray

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "clock", registering: [
        "use24Hour": true,
        "showSeconds": false,
        "showDate": true,
    ])

    var use24Hour: Bool { didSet { store.set(use24Hour, "use24Hour") } }
    var showSeconds: Bool { didSet { store.set(showSeconds, "showSeconds") } }
    var showDate: Bool { didSet { store.set(showDate, "showDate") } }

    init() {
        use24Hour = store.bool("use24Hour")
        showSeconds = store.bool("showSeconds")
        showDate = store.bool("showDate")
    }

    func expandedView() -> AnyView { AnyView(ClockView(module: self)) }
    func settingsView() -> AnyView? { AnyView(ClockSettingsView(module: self)) }
}

private struct ClockView: View {
    let module: ClockModule

    /// Format explicite : le format « 2 chiffres » de la locale anglaise repasse en 12 h.
    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = IslandSettings.shared.locale
        let seconds = module.showSeconds ? ":ss" : ""
        formatter.dateFormat = module.use24Hour ? "HH:mm\(seconds)" : "h:mm\(seconds) a"
        return formatter.string(from: date)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(time(context.date))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if module.showDate {
                    Text(context.date.formatted(.dateTime.locale(IslandSettings.shared.locale).weekday(.wide).day().month(.wide))
                        .capitalizingFirstLetter)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(Color.primary)
        }
    }
}

private struct ClockSettingsView: View {
    @Bindable var module: ClockModule

    var body: some View {
        ToggleRow(tr("Format 24 heures", "24-hour time"), isOn: $module.use24Hour)
        ToggleRow(tr("Afficher les secondes", "Show seconds"), isOn: $module.showSeconds)
        ToggleRow(tr("Afficher la date", "Show date"), isOn: $module.showDate)
    }
}

extension String {
    /// « dimanche 4 octobre » → « Dimanche 4 octobre » (`capitalized` mettrait aussi une majuscule au mois).
    var capitalizingFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
