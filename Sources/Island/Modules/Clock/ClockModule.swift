import SwiftUI

@MainActor
@Observable
final class ClockModule: IslandModule {
    let id = "clock"
    let name = "Date & heure"
    let systemImage = "clock"
    let summary = "Affiche l'heure et la date du jour."
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date.formatted(.dateTime.locale(.current)
                    .hour(module.use24Hour ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated))
                    .minute(.twoDigits)
                    .second(module.showSeconds ? .twoDigits : .omitted)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if module.showDate {
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizingFirstLetter)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

private struct ClockSettingsView: View {
    @Bindable var module: ClockModule

    var body: some View {
        ToggleRow("Format 24 heures", isOn: $module.use24Hour)
        ToggleRow("Afficher les secondes", isOn: $module.showSeconds)
        ToggleRow("Afficher la date", isOn: $module.showDate)
    }
}

extension String {
    /// « dimanche 4 octobre » → « Dimanche 4 octobre » (`capitalized` mettrait aussi une majuscule au mois).
    var capitalizingFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
