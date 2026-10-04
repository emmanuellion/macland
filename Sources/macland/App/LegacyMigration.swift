import Foundation

/// Reprise des données de l'ancien nom de l'app (« Island », identifiant local.elion.island) :
/// réglages et dossier Application Support (étagère, historique du presse-papiers).
/// Sans effet si rien n'existe ou si la migration a déjà eu lieu.
enum LegacyMigration {
    private static let legacyDomain = "local.elion.island"
    private static let doneKey = "migratedFromIsland"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        if let legacy = defaults.persistentDomain(forName: legacyDomain) {
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        let support = URL.applicationSupportDirectory
        let oldFolder = support.appending(path: "Island", directoryHint: .isDirectory)
        let newFolder = support.appending(path: "macland", directoryHint: .isDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: oldFolder.path), !fileManager.fileExists(atPath: newFolder.path) {
            try? fileManager.moveItem(at: oldFolder, to: newFolder)
        }

        defaults.set(true, forKey: doneKey)
    }
}
