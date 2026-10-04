import SwiftUI

enum ModuleKind {
    /// Widget affiché côte à côte avec les autres sur la page d'accueil de l'île.
    case widget
    /// Module qui occupe sa propre page (onglet) dans l'île ouverte.
    case page
    /// Module sans affichage dans l'île ouverte (ex. : HUD, indicateurs) : seulement des activités en direct.
    case background
}

/// Un élément affichable dans l'île (horloge, batterie, musique, calendrier…).
///
/// Pour ajouter un module : créer une classe conforme à ce protocole,
/// puis l'enregistrer dans `ModuleRegistry.allModules`.
@MainActor
protocol IslandModule: AnyObject {
    /// Identifiant stable, utilisé comme clé de persistance. Ne pas le changer une fois publié.
    var id: String { get }
    var name: String { get }
    var systemImage: String { get }
    var summary: String { get }
    /// Couleur de l'icône dans les réglages.
    var tint: Color { get }
    var kind: ModuleKind { get }
    var enabledByDefault: Bool { get }
    /// Widget prioritaire pour la largeur sur l'accueil (les autres prennent leur taille idéale).
    var layoutPriority: Double { get }
    /// Un widget peut se masquer temporairement de l'accueil (ex. : rien en lecture).
    var isVisibleInHome: Bool { get }

    /// Contenu affiché dans l'île ouverte (widget ou page selon `kind`).
    func expandedView() -> AnyView

    /// Lignes de réglages spécifiques au module (`SettingsRow`, `ToggleRow`…). `nil` si aucun.
    func settingsView() -> AnyView?

    /// Appelé quand le module est activé (démarrer timers, observateurs…).
    func start()

    /// Appelé quand le module est désactivé : libérer les ressources.
    func stop()
}

extension IslandModule {
    var tint: Color { .accentColor }
    var kind: ModuleKind { .widget }
    var enabledByDefault: Bool { true }
    var layoutPriority: Double { 0 }
    var isVisibleInHome: Bool { true }
    func settingsView() -> AnyView? { nil }
    func start() {}
    func stop() {}
}

/// Module capable de recevoir des fichiers déposés sur l'encoche.
@MainActor
protocol FileDropReceiving: IslandModule {
    var isDropTargeted: Bool { get set }
    func receive(_ providers: [NSItemProvider]) -> Bool
}

/// Accès aux UserDefaults sous un préfixe propre à un module (`module.<id>.<clé>`).
struct ModuleDefaults {
    let moduleID: String
    private let defaults = UserDefaults.standard

    init(moduleID: String, registering values: [String: Any]) {
        self.moduleID = moduleID
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: values.map { (key($0.key), $0.value) }))
    }

    private func key(_ name: String) -> String { "module.\(moduleID).\(name)" }

    func bool(_ name: String) -> Bool { defaults.bool(forKey: key(name)) }
    func double(_ name: String) -> Double { defaults.double(forKey: key(name)) }
    func string(_ name: String) -> String { defaults.string(forKey: key(name)) ?? "" }
    func strings(_ name: String) -> [String] { defaults.stringArray(forKey: key(name)) ?? [] }
    func set(_ value: Any, _ name: String) { defaults.set(value, forKey: key(name)) }
}
