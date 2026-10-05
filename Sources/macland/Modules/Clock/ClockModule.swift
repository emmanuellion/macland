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
    private func time(_ date: Date, seconds: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = IslandSettings.shared.locale
        let secondsFormat = seconds ? ":ss" : ""
        formatter.dateFormat = module.use24Hour ? "HH:mm\(secondsFormat)" : "h:mm\(secondsFormat) a"
        return formatter.string(from: date)
    }

    private func date(_ date: Date, short: Bool) -> String {
        let style = Date.FormatStyle.dateTime.locale(IslandSettings.shared.locale)
        let text = short
            ? date.formatted(style.weekday(.abbreviated).day().month(.abbreviated))
            : date.formatted(style.weekday(.wide).day().month(.wide))
        return text.capitalizingFirstLetter
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            // Du plus complet au plus compact : l'île garde la première variante qui tient.
            ViewThatFits(in: .horizontal) {
                variant(context.date, size: 34, seconds: module.showSeconds, shortDate: false)
                variant(context.date, size: 30, seconds: false, shortDate: true)
                Text(time(context.date, seconds: false))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Color.primary)
        }
    }

    private func variant(_ now: Date, size: CGFloat, seconds: Bool, shortDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time(now, seconds: seconds))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if module.showDate {
                Text(date(now, short: shortDate))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
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
