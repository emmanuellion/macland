import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, french, english

    var id: String { rawValue }

    /// Nom affiché dans sa propre langue.
    var label: String {
        switch self {
        case .system: tr("Système", "System")
        case .french: "Français"
        case .english: "English"
        }
    }
}

/// Texte de l'interface dans la langue choisie (français ou anglais).
/// Lit un réglage observable : les vues se mettent à jour dès qu'on change de langue.
func tr(_ french: String, _ english: String) -> String {
    IslandSettings.shared.isFrench ? french : english
}

extension IslandSettings {
    /// Langue effective : le choix de l'utilisateur, sinon celle du système (français si préféré, anglais sinon).
    var isFrench: Bool {
        switch language {
        case .french: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("fr") ?? false
        }
    }

    /// Locale des dates et nombres, accordée à la langue de l'interface.
    var locale: Locale { Locale(identifier: isFrench ? "fr_FR" : "en_US") }
}
