import AppKit
import Observation
import SwiftUI

/// Couleur d'accent des éléments de l'île (onglet sélectionné, curseurs, progression).
enum IslandAccent: String, CaseIterable, Identifiable {
    case neutral, blue, purple, pink, orange, green

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .neutral: .primary
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        }
    }

    var label: String {
        switch self {
        case .neutral: tr("Neutre", "Neutral")
        case .blue: tr("Bleu", "Blue")
        case .purple: tr("Violet", "Purple")
        case .pink: tr("Rose", "Pink")
        case .orange: tr("Orange", "Orange")
        case .green: tr("Vert", "Green")
        }
    }
}

/// Thème de la fenêtre de réglages.
enum SettingsTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: tr("Système", "System")
        case .light: tr("Clair", "Light")
        case .dark: tr("Sombre", "Dark")
        }
    }

    /// `nil` = suit l'apparence de macOS.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Matière de l'île ouverte.
enum IslandMaterial: String, CaseIterable, Identifiable {
    case solid
    /// Liquid Glass (macOS 26+), teinté par la couleur choisie.
    case glass

    var id: String { rawValue }
    static var isGlassAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

/// Variante du verre : standard (plus diffus) ou clair (plus transparent).
enum GlassVariant: String, CaseIterable, Identifiable {
    case regular, clear
    var id: String { rawValue }
}

/// Couleur de l'île ouverte. Fermée, l'île reste noire pour se fondre dans l'encoche (la caméra est noire).
enum IslandColor: String, CaseIterable, Identifiable {
    case black, blue, pink, lavender, mint

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .black: .black
        case .blue: Color(red: 0.72, green: 0.84, blue: 0.98)
        case .pink: Color(red: 0.98, green: 0.78, blue: 0.85)
        case .lavender: Color(red: 0.82, green: 0.78, blue: 0.98)
        case .mint: Color(red: 0.74, green: 0.93, blue: 0.84)
        }
    }

    var label: String {
        switch self {
        case .black: tr("Noir", "Black")
        case .blue: tr("Bleu pastel", "Pastel blue")
        case .pink: tr("Rose pastel", "Pastel pink")
        case .lavender: tr("Lavande", "Lavender")
        case .mint: tr("Menthe", "Mint")
        }
    }

    /// Les teintes pastel prennent un texte sombre.
    var isDark: Bool { self == .black }
    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

enum ExpandTrigger: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hover: tr("Survol", "Hover")
        case .click: tr("Clic", "Click")
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

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }

    /// Masque l'île quand une app est en plein écran (vidéo, jeu…).
    var hideInFullScreen: Bool {
        didSet { defaults.set(hideInFullScreen, forKey: "hideInFullScreen") }
    }

    /// Rouvre toujours l'île sur l'accueil (sinon sur le dernier onglet utilisé).
    var alwaysOpenOnHome: Bool {
        didSet { defaults.set(alwaysOpenOnHome, forKey: "alwaysOpenOnHome") }
    }

    /// Marge (pt) autour de l'encoche qui déclenche le survol.
    var hoverPadding: Double {
        didSet { defaults.set(hoverPadding, forKey: "hoverPadding") }
    }

    /// Un clic en dehors de l'île la referme.
    var closeOnClickOutside: Bool {
        didSet { defaults.set(closeOnClickOutside, forKey: "closeOnClickOutside") }
    }

    /// Fin contour autour de l'île ouverte.
    var islandBorder: Bool {
        didSet { defaults.set(islandBorder, forKey: "islandBorder") }
    }

    /// Intensité de l'ombre portée (0…1).
    var shadowOpacity: Double {
        didSet { defaults.set(shadowOpacity, forKey: "shadowOpacity") }
    }

    /// Bouton des réglages en haut à droite de l'île ouverte.
    var showSettingsButton: Bool {
        didSet { defaults.set(showSettingsButton, forKey: "showSettingsButton") }
    }

    var islandAccent: IslandAccent {
        didSet { defaults.set(islandAccent.rawValue, forKey: "islandAccent") }
    }

    var settingsTheme: SettingsTheme {
        didSet { defaults.set(settingsTheme.rawValue, forKey: "settingsTheme") }
    }

    /// L'écran d'accueil du premier lancement a été vu.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
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

    var islandColor: IslandColor {
        didSet { defaults.set(islandColor.rawValue, forKey: "islandColor") }
    }

    var islandMaterial: IslandMaterial {
        didSet { defaults.set(islandMaterial.rawValue, forKey: "islandMaterial") }
    }

    var glassVariant: GlassVariant {
        didSet { defaults.set(glassVariant.rawValue, forKey: "glassVariant") }
    }

    /// Intensité de la teinte posée sur le verre (0 = verre pur, 1 = couleur presque opaque).
    var glassTint: Double {
        didSet { defaults.set(glassTint, forKey: "glassTint") }
    }

    /// Le verre n'est utilisé que si le système le permet.
    var usesGlass: Bool { islandMaterial == .glass && IslandMaterial.isGlassAvailable }

    /// Filets verticaux entre les widgets de l'accueil.
    var showWidgetSeparators: Bool {
        didSet { defaults.set(showWidgetSeparators, forKey: "showWidgetSeparators") }
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
        "islandMaterial": IslandMaterial.solid.rawValue,
        "glassVariant": GlassVariant.regular.rawValue,
        "glassTint": 0.45,
        "expandedWidth": 680.0,
        "expandedHeight": 190.0,
        "expandedCornerRadius": 30.0,
        "animationResponse": 0.42,
        "animationBounce": 0.22,
        "showShadow": true,
        "showWidgetSeparators": false,
        "islandColor": IslandColor.black.rawValue,
    ]

    private init() {
        defaults.register(defaults: Self.appearanceDefaults.merging([
            "expandTrigger": ExpandTrigger.hover.rawValue,
            "hoverDelay": 0.15,
            "collapseDelay": 0.35,
            "hapticFeedback": true,
            "showOnScreensWithoutNotch": false,
            "showMenuBarIcon": true,
            "language": AppLanguage.system.rawValue,
            "settingsTheme": SettingsTheme.system.rawValue,
            "hideInFullScreen": true,
            "alwaysOpenOnHome": false,
            "hoverPadding": 4.0,
            "closeOnClickOutside": true,
            "islandBorder": false,
            "shadowOpacity": 0.45,
            "showSettingsButton": true,
            "islandAccent": IslandAccent.neutral.rawValue,
            "hasCompletedOnboarding": false,
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
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        settingsTheme = SettingsTheme(rawValue: defaults.string(forKey: "settingsTheme") ?? "") ?? .system
        hideInFullScreen = defaults.bool(forKey: "hideInFullScreen")
        alwaysOpenOnHome = defaults.bool(forKey: "alwaysOpenOnHome")
        hoverPadding = defaults.double(forKey: "hoverPadding")
        closeOnClickOutside = defaults.bool(forKey: "closeOnClickOutside")
        islandBorder = defaults.bool(forKey: "islandBorder")
        shadowOpacity = defaults.double(forKey: "shadowOpacity")
        showSettingsButton = defaults.bool(forKey: "showSettingsButton")
        islandAccent = IslandAccent(rawValue: defaults.string(forKey: "islandAccent") ?? "") ?? .neutral
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        liveActivitiesEnabled = defaults.bool(forKey: "liveActivitiesEnabled")
        expandedWidth = defaults.double(forKey: "expandedWidth")
        expandedHeight = defaults.double(forKey: "expandedHeight")
        expandedCornerRadius = defaults.double(forKey: "expandedCornerRadius")
        animationResponse = defaults.double(forKey: "animationResponse")
        animationBounce = defaults.double(forKey: "animationBounce")
        showShadow = defaults.bool(forKey: "showShadow")
        showWidgetSeparators = defaults.bool(forKey: "showWidgetSeparators")
        islandColor = IslandColor(rawValue: defaults.string(forKey: "islandColor") ?? "") ?? .black
        islandMaterial = IslandMaterial(rawValue: defaults.string(forKey: "islandMaterial") ?? "") ?? .solid
        glassVariant = GlassVariant(rawValue: defaults.string(forKey: "glassVariant") ?? "") ?? .regular
        glassTint = defaults.double(forKey: "glassTint")
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
        showWidgetSeparators = defaults.bool(forKey: "showWidgetSeparators")
        islandColor = IslandColor(rawValue: defaults.string(forKey: "islandColor") ?? "") ?? .black
        islandMaterial = IslandMaterial(rawValue: defaults.string(forKey: "islandMaterial") ?? "") ?? .solid
        glassVariant = GlassVariant(rawValue: defaults.string(forKey: "glassVariant") ?? "") ?? .regular
        glassTint = defaults.double(forKey: "glassTint")
    }
}
