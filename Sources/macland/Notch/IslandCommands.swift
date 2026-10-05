import Foundation

/// Ordres envoyés à l'île par les modules (ou un raccourci clavier), sans dépendre des fenêtres.
@MainActor
enum IslandCommands {
    static let openPageNotification = Notification.Name("IslandOpenPage")
    static let collapseNotification = Notification.Name("IslandCollapse")
    static let showOnboardingNotification = Notification.Name("IslandShowOnboarding")

    /// Rouvre l'écran d'accueil.
    static func showOnboarding() {
        NotificationCenter.default.post(name: showOnboardingNotification, object: nil)
    }

    /// Ouvre l'île sur une page (`NotchViewModel.homePage` ou l'identifiant d'un module de type `.page`).
    static func open(page: String) {
        NotificationCenter.default.post(name: openPageNotification, object: page)
    }

    static func collapse() {
        NotificationCenter.default.post(name: collapseNotification, object: nil)
    }
}
