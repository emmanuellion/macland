import AppKit
import Observation

/// État d'une île (une par écran).
@MainActor
@Observable
final class NotchViewModel {
    static let homePage = "home"

    var geometry: NotchGeometry
    private(set) var isExpanded = false
    /// Page affichée dans l'île ouverte : `homePage` ou l'identifiant d'un module de type `.page`.
    var selectedPage = NotchViewModel.homePage

    @ObservationIgnored private let settings = IslandSettings.shared

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    static let collapsedTopRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 10
    static let expandedTopRadius: CGFloat = 14

    var activity: LiveActivity? { ActivityCenter.shared.current }

    var topRadius: CGFloat { isExpanded ? Self.expandedTopRadius : Self.collapsedTopRadius }
    var bottomRadius: CGFloat {
        if isExpanded { return settings.expandedCornerRadius }
        return activity?.bottom != nil ? 18 : Self.collapsedBottomRadius
    }

    /// Taille de la forme dessinée (oreilles supérieures incluses).
    var shapeSize: CGSize {
        let notch = geometry.size
        if isExpanded {
            return CGSize(width: max(settings.expandedWidth, notch.width + 2 * topRadius),
                          height: max(settings.expandedHeight, notch.height))
        }
        if let activity {
            return CGSize(width: notch.width + 2 * (activity.sideWidth + topRadius),
                          height: notch.height + activity.bottomHeight)
        }
        return CGSize(width: notch.width + 2 * topRadius, height: notch.height)
    }

    /// Revient à l'accueil si la page sélectionnée n'existe plus (module désactivé).
    func validateSelectedPage() {
        if selectedPage != Self.homePage,
           !ModuleRegistry.shared.enabledPages.contains(where: { $0.id == selectedPage }) {
            selectedPage = Self.homePage
        }
    }

    func expand(page: String? = nil) {
        if let page {
            selectedPage = page
        } else if !isExpanded, settings.alwaysOpenOnHome {
            selectedPage = Self.homePage
        }
        validateSelectedPage()
        guard !isExpanded else { return }
        isExpanded = true
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func collapse() {
        isExpanded = false
    }

    func toggle() {
        isExpanded ? collapse() : expand()
    }
}
