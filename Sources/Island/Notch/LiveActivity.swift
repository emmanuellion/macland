import SwiftUI

/// Information brève affichée de part et d'autre de l'encoche fermée
/// (ex. : branchement du chargeur, rappel d'événement).
struct LiveActivity {
    let id: String
    /// L'activité de plus haute priorité est affichée ; à égalité, la plus récente.
    var priority = 0
    /// Durée d'affichage en secondes. `nil` = jusqu'à `dismiss`.
    var duration: TimeInterval? = 4
    /// Largeur de chaque côté de l'encoche.
    var sideWidth: CGFloat = 74
    /// Hauteur d'une zone optionnelle sous l'encoche (ex. : barre du HUD volume).
    var bottomHeight: CGFloat = 0
    /// Activité manipulable à la souris : le survol ne déplie pas l'île et prolonge l'affichage.
    var isInteractive = false
    let leading: AnyView
    let trailing: AnyView
    let bottom: AnyView?

    init<Leading: View, Trailing: View>(
        id: String,
        priority: Int = 0,
        duration: TimeInterval? = 4,
        sideWidth: CGFloat = 74,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.id = id
        self.priority = priority
        self.duration = duration
        self.sideWidth = sideWidth
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
        self.bottom = nil
    }

    init<Leading: View, Trailing: View, Bottom: View>(
        id: String,
        priority: Int = 0,
        duration: TimeInterval? = 4,
        sideWidth: CGFloat = 74,
        bottomHeight: CGFloat,
        isInteractive: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.id = id
        self.priority = priority
        self.duration = duration
        self.sideWidth = sideWidth
        self.bottomHeight = bottomHeight
        self.isInteractive = isInteractive
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
        self.bottom = AnyView(bottom())
    }
}

@MainActor
@Observable
final class ActivityCenter {
    static let shared = ActivityCenter()

    private var activities: [LiveActivity] = []
    @ObservationIgnored private var expirations: [String: DispatchWorkItem] = [:]

    var current: LiveActivity? {
        guard IslandSettings.shared.liveActivitiesEnabled,
              let top = activities.map(\.priority).max()
        else { return nil }
        return activities.last { $0.priority == top }
    }

    private init() {}

    func show(_ activity: LiveActivity) {
        // Remplacement sur place : garde la position dans la liste (pas d'animation parasite).
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        scheduleExpiration(of: activity)
    }

    /// Repousse la fin d'une activité (ex. : la souris est dessus).
    func extend(_ id: String) {
        guard let activity = activities.first(where: { $0.id == id }) else { return }
        scheduleExpiration(of: activity)
    }

    private func scheduleExpiration(of activity: LiveActivity) {
        expirations.removeValue(forKey: activity.id)?.cancel()
        guard let duration = activity.duration else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss(activity.id) }
        }
        expirations[activity.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismiss(_ id: String) {
        expirations.removeValue(forKey: id)?.cancel()
        activities.removeAll { $0.id == id }
    }
}
