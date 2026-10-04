import Foundation
import Observation

enum ExpandTrigger: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hover: "Survol"
        case .click: "Clic"
        }
    }
}

/// Réglages globaux de l'île, persistés dans UserDefaults.
/// Les réglages propres à chaque module vivent dans le module lui-même (voir `ModuleDefaults`).
@Observable
final class IslandSettings {
    static let shared = IslandSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: Comportement

    var expandTrigger: ExpandTrigger {
        didSet { defaults.set(expandTrigger.rawValue, forKey: "expandTrigger") }
    }

    /// Délai avant ouverture au survol (secondes).
    var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: "hoverDelay") }
    }

    /// Délai avant fermeture quand la souris quitte l'île (secondes).
    var collapseDelay: Double {
        didSet { defaults.set(collapseDelay, forKey: "collapseDelay") }
    }

    var hapticFeedback: Bool {
        didSet { defaults.set(hapticFeedback, forKey: "hapticFeedback") }
    }

    var showOnScreensWithoutNotch: Bool {
        didSet { defaults.set(showOnScreensWithoutNotch, forKey: "showOnScreensWithoutNotch") }
    }

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    // MARK: Activités en direct

    /// Affichage d'informations brèves autour de l'encoche fermée (charge, rappels…).
    var liveActivitiesEnabled: Bool {
        didSet { defaults.set(liveActivitiesEnabled, forKey: "liveActivitiesEnabled") }
    }

    // MARK: Apparence

    var expandedWidth: Double {
        didSet { defaults.set(expandedWidth, forKey: "expandedWidth") }
    }

    var expandedHeight: Double {
        didSet { defaults.set(expandedHeight, forKey: "expandedHeight") }
    }

    var expandedCornerRadius: Double {
        didSet { defaults.set(expandedCornerRadius, forKey: "expandedCornerRadius") }
    }

    /// Durée perçue de l'animation ressort (secondes).
    var animationResponse: Double {
        didSet { defaults.set(animationResponse, forKey: "animationResponse") }
    }

    /// Rebond de l'animation (0 = aucun, 0.5 = très élastique).
    var animationBounce: Double {
        didSet { defaults.set(animationBounce, forKey: "animationBounce") }
    }

    var showShadow: Bool {
        didSet { defaults.set(showShadow, forKey: "showShadow") }
    }

    // MARK: Modules

    /// Ordre d'affichage des modules (identifiants).
    var moduleOrder: [String] {
        didSet { defaults.set(moduleOrder, forKey: "moduleOrder") }
    }

    /// Activation explicite choisie par l'utilisateur. Absent = valeur par défaut du module.
    var moduleEnabled: [String: Bool] {
        didSet { defaults.set(moduleEnabled, forKey: "moduleEnabled") }
    }

    private static let appearanceDefaults: [String: Any] = [
        "expandedWidth": 680.0,
        "expandedHeight": 190.0,
        "expandedCornerRadius": 30.0,
        "animationResponse": 0.42,
        "animationBounce": 0.22,
        "showShadow": true,
    ]

    private init() {
        defaults.register(defaults: Self.appearanceDefaults.merging([
            "expandTrigger": ExpandTrigger.hover.rawValue,
            "hoverDelay": 0.15,
            "collapseDelay": 0.35,
            "hapticFeedback": true,
            "showOnScreensWithoutNotch": false,
            "showMenuBarIcon": true,
            "liveActivitiesEnabled": true,
            "moduleOrder": [String](),
            "moduleEnabled": [String: Bool](),
        ]) { $1 })

        expandTrigger = ExpandTrigger(rawValue: defaults.string(forKey: "expandTrigger") ?? "") ?? .hover
        hoverDelay = defaults.double(forKey: "hoverDelay")
        collapseDelay = defaults.double(forKey: "collapseDelay")
        hapticFeedback = defaults.bool(forKey: "hapticFeedback")
        showOnScreensWithoutNotch = defaults.bool(forKey: "showOnScreensWithoutNotch")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        liveActivitiesEnabled = defaults.bool(forKey: "liveActivitiesEnabled")
        expandedWidth = defaults.double(forKey: "expandedWidth")
        expandedHeight = defaults.double(forKey: "expandedHeight")
        expandedCornerRadius = defaults.double(forKey: "expandedCornerRadius")
        animationResponse = defaults.double(forKey: "animationResponse")
        animationBounce = defaults.double(forKey: "animationBounce")
        showShadow = defaults.bool(forKey: "showShadow")
        moduleOrder = defaults.stringArray(forKey: "moduleOrder") ?? []
        moduleEnabled = defaults.dictionary(forKey: "moduleEnabled") as? [String: Bool] ?? [:]
    }

    func resetAppearance() {
        Self.appearanceDefaults.keys.forEach(defaults.removeObject(forKey:))
        expandedWidth = defaults.double(forKey: "expandedWidth")
        expandedHeight = defaults.double(forKey: "expandedHeight")
        expandedCornerRadius = defaults.double(forKey: "expandedCornerRadius")
        animationResponse = defaults.double(forKey: "animationResponse")
        animationBounce = defaults.double(forKey: "animationBounce")
        showShadow = defaults.bool(forKey: "showShadow")
    }
}
