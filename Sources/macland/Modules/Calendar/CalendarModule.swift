import EventKit
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: Color
}

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let source: String
    let color: Color
}

enum CalendarAccess {
    case notDetermined, granted, denied
}

@MainActor
@Observable
final class CalendarModule: IslandModule {
    let id = "calendar"
    var name: String { tr("Calendrier", "Calendar") }
    let systemImage = "calendar"
    var summary: String {
        tr("Prochains événements et rappel juste avant qu'ils commencent.",
           "Upcoming events and a reminder just before they start.")
    }
    let tint = Color.red
    let enabledByDefault = false

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "calendar", registering: [
        "maxEvents": 3.0,
        "daysAhead": 1.0,
        "showAllDay": true,
        "showLocation": false,
        "alertMinutesBefore": 5.0,
        "hiddenCalendars": [String](),
    ])

    var maxEvents: Double { didSet { store.set(maxEvents, "maxEvents") } }
    /// Nombre de jours affichés (1 = aujourd'hui uniquement).
    var daysAhead: Double { didSet { store.set(daysAhead, "daysAhead"); refresh() } }
    var showAllDay: Bool { didSet { store.set(showAllDay, "showAllDay"); refresh() } }
    var showLocation: Bool { didSet { store.set(showLocation, "showLocation") } }
    /// Minutes avant le début pour l'activité de rappel (0 = désactivé).
    var alertMinutesBefore: Double { didSet { store.set(alertMinutesBefore, "alertMinutesBefore") } }
    var hiddenCalendars: Set<String> { didSet { store.set(Array(hiddenCalendars), "hiddenCalendars"); refresh() } }

    private(set) var access = CalendarAccess.notDetermined
    private(set) var events: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var alertedEventIDs: Set<String> = []

    init() {
        maxEvents = store.double("maxEvents")
        daysAhead = store.double("daysAhead")
        showAllDay = store.bool("showAllDay")
        showLocation = store.bool("showLocation")
        alertMinutesBefore = store.double("alertMinutesBefore")
        hiddenCalendars = Set(store.strings("hiddenCalendars"))
    }

    func expandedView() -> AnyView { AnyView(CalendarView(module: self)) }
    func settingsView() -> AnyView? { AnyView(CalendarSettingsView(module: self)) }

    func start() {
        updateAccess()
        if access == .notDetermined {
            Task { await requestAccess() }
        }

        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        ActivityCenter.shared.dismiss("calendar.alert")
    }

    func requestAccess() async {
        _ = try? await eventStore.requestFullAccessToEvents()
        updateAccess()
        refresh()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: access = .granted
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
    }

    func refresh() {
        guard access == .granted else {
            events = []
            return
        }

        let allCalendars = eventStore.calendars(for: .event)
        calendars = allCalendars
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title, color: Color(cgColor: $0.cgColor)) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }

        let visible = allCalendars.filter { !hiddenCalendars.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else {
            events = []
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: max(1, Int(daysAhead)), to: startOfDay) ?? now
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: end, calendars: visible)

        events = eventStore.events(matching: predicate)
            .filter { $0.endDate > now && (showAllDay || !$0.isAllDay) }
            .sorted { $0.startDate < $1.startDate }
            .map {
                CalendarEvent(id: $0.calendarItemIdentifier + "\($0.startDate.timeIntervalSince1970)",
                              title: $0.title ?? tr("Sans titre", "Untitled"),
                              start: $0.startDate,
                              end: $0.endDate,
                              isAllDay: $0.isAllDay,
                              location: $0.location?.isEmpty == false ? $0.location : nil,
                              color: Color(cgColor: $0.calendar.cgColor))
            }

        checkUpcomingAlert(now: now)
    }

    private func checkUpcomingAlert(now: Date) {
        guard alertMinutesBefore > 0 else { return }
        let window = alertMinutesBefore * 60
        guard let event = events.first(where: {
            !$0.isAllDay && !alertedEventIDs.contains($0.id)
                && $0.start > now && $0.start.timeIntervalSince(now) <= window
        }) else { return }

        alertedEventIDs.insert(event.id)
        let minutes = max(1, Int((event.start.timeIntervalSince(now) / 60).rounded()))
        ActivityCenter.shared.show(LiveActivity(id: "calendar.alert", priority: 2, duration: 10) {
            HStack(spacing: 5) {
                Circle().fill(event.color).frame(width: 7, height: 7)
                Text(event.title).lineLimit(1)
            }
        } trailing: {
            Text(tr("dans \(minutes) min", "in \(minutes) min")).foregroundStyle(event.color)
        })
    }
}

// MARK: - Vue

private struct CalendarView: View {
    let module: CalendarModule

    var body: some View {
        switch module.access {
        case .granted:
            let events = Array(module.events.prefix(Int(module.maxEvents)))
            if events.isEmpty {
                Label(tr("Rien de prévu", "Nothing scheduled"), systemImage: "calendar.badge.checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(events) { event in
                        EventRow(event: event, showLocation: module.showLocation)
                    }
                }
            }
        case .notDetermined:
            Button(tr("Autoriser l'accès au calendrier", "Allow calendar access")) { Task { await module.requestAccess() } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.7))
        case .denied:
            Button { module.openPrivacySettings() } label: {
                Label(tr("Accès refusé : ouvrir les réglages", "Access denied: open Settings"), systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.7))
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let showLocation: Bool

    private var timeLabel: String {
        let calendar = Calendar.current
        let locale = IslandSettings.shared.locale
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        var day = ""
        if !calendar.isDateInToday(event.start) {
            day = calendar.isDateInTomorrow(event.start)
                ? tr("Demain ", "Tomorrow ")
                : event.start.formatted(.dateTime.locale(locale).weekday(.abbreviated)).capitalizingFirstLetter + " "
        }
        if event.isAllDay { return day + tr("Journée", "All day") }
        if event.start <= .now { return tr("En cours · fin \(event.end.formatted(time))", "Now · ends \(event.end.formatted(time))") }
        return day + event.start.formatted(time)
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timeLabel)
                    if showLocation, let location = event.location {
                        Text("· \(location)").lineLimit(1)
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.55))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Réglages

private struct CalendarSettingsView: View {
    @Bindable var module: CalendarModule

    var body: some View {
        if module.access != .granted {
            SettingsRow(tr("Accès au calendrier", "Calendar access"),
                        subtitle: module.access == .denied
                            ? tr("Refusé. Autorise macland dans Confidentialité et sécurité › Calendriers.",
                                 "Denied. Allow macland in Privacy & Security › Calendars.")
                            : tr("macland a besoin de l'accès pour afficher tes événements.",
                                 "macland needs access to show your events.")) {
                Button(module.access == .denied ? tr("Ouvrir les réglages", "Open Settings") : tr("Autoriser", "Allow")) {
                    if module.access == .denied {
                        module.openPrivacySettings()
                    } else {
                        Task { await module.requestAccess() }
                    }
                }
            }
        }
        SettingsSubheader(tr("Affichage", "Display"))
        StepperRow(tr("Événements affichés", "Events shown"), value: $module.maxEvents, range: 1...5)
        PickerRow(tr("Période", "Range"), selection: $module.daysAhead) {
            Text(tr("Aujourd'hui", "Today")).tag(1.0)
            Text(tr("2 jours", "2 days")).tag(2.0)
            Text(tr("Semaine", "Week")).tag(7.0)
        }
        ToggleRow(tr("Événements sur la journée", "All-day events"), isOn: $module.showAllDay)
        ToggleRow(tr("Afficher le lieu", "Show location"), isOn: $module.showLocation)
        SettingsSubheader(tr("Rappels", "Reminders"))
        PickerRow(tr("Rappel avant le début", "Reminder before start"),
                  subtitle: tr("Activité en direct autour de l'encoche.", "Live activity around the notch."),
                  selection: $module.alertMinutesBefore) {
            Text(tr("Non", "Off")).tag(0.0)
            Text("1 min").tag(1.0)
            Text("5 min").tag(5.0)
            Text("10 min").tag(10.0)
            Text("15 min").tag(15.0)
        }
        if !module.calendars.isEmpty {
            SettingsSubheader(tr("Calendriers affichés", "Calendars shown"))
        }
        ForEach(module.calendars) { calendar in
            ToggleRow(calendar.title, subtitle: calendar.source, leadingColor: calendar.color, isOn: Binding(
                get: { !module.hiddenCalendars.contains(calendar.id) },
                set: { visible in
                    if visible { module.hiddenCalendars.remove(calendar.id) } else { module.hiddenCalendars.insert(calendar.id) }
                }
            ))
        }
    }
}
