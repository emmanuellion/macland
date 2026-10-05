import Foundation

/// Choix du fond d'écran système, écrit directement dans le registre de macOS
/// (~/Library/Application Support/com.apple.wallpaper/Store/Index.plist).
///
/// C'est ce que fait Réglages › Fond d'écran quand on choisit un fond animé : le choix
/// « aerials » + l'identifiant de la vidéo, pour chaque écran et chaque Space. macland l'écrit
/// lui-même pour que l'utilisateur n'ait rien à faire ; l'original est sauvegardé avant.
@MainActor
enum SystemWallpaperChoice {
    private static let storeFile = URL.homeDirectory.appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    private static let backupFile = WallpaperLibrary.directory.appending(path: "Index.plist.backup")
    private static let aerialProvider = "com.apple.wallpaper.choice.aerials"

    /// Un écran ou un Space affiche-t-il actuellement une vidéo de macland ?
    static var selectedMaclandAsset: String? {
        guard let store = try? readStore() else { return nil }
        return maclandAssets(in: store).first
    }

    /// Met la vidéo `assetID` (déjà présente dans le catalogue) en fond de tous les écrans et Spaces.
    /// Le fond est aussi celui de l'écran de verrouillage.
    static func select(assetID: String) throws {
        var store = try readStore()
        backUpOnce()
        let choice: [String: Any] = [
            "Provider": aerialProvider,
            "Configuration": try PropertyListSerialization.data(fromPropertyList: ["assetID": assetID], format: .binary, options: 0),
            "Files": [Any](),
        ]
        // Tous les nœuds « Desktop » : chaque écran, chaque Space, et le réglage par défaut
        // (« SystemDefault ») dont héritent les nouveaux Spaces.
        store = replacingDesktopChoices(in: store, with: choice) as? [String: Any] ?? store
        try writeStore(store)
        restartAgent()
    }

    /// Remet le fond d'origine, seulement là où macland a mis sa vidéo : les autres réglages
    /// (écrans ajoutés, Spaces, économiseur…) faits depuis sont conservés.
    static func restore() {
        guard FileManager.default.fileExists(atPath: backupFile.path) else { return }
        defer { try? FileManager.default.removeItem(at: backupFile) }
        guard var store = try? readStore(), !maclandAssets(in: store).isEmpty,
              let backupData = try? Data(contentsOf: backupFile),
              let backup = try? PropertyListSerialization.propertyList(from: backupData, format: nil) as? [String: Any]
        else { return }
        let fallback = ((backup["SystemDefault"] as? [String: Any])?["Desktop"] as? [String: Any])?["Content"]
        store = restoringMaclandChoices(in: store, backup: backup, fallback: fallback) as? [String: Any] ?? store
        try? writeStore(store)
        restartAgent()
    }

    /// Remplace le contenu des nœuds « Desktop » qui affichent une vidéo macland par celui du même
    /// nœud dans la sauvegarde (ou, à défaut, par le réglage par défaut d'origine).
    private static func restoringMaclandChoices(in node: Any, backup: Any?, fallback: Any?) -> Any {
        guard var dictionary = node as? [String: Any] else { return node }
        let backupDictionary = backup as? [String: Any]
        for (key, value) in dictionary {
            if key == "Desktop", var desktop = value as? [String: Any], !maclandAssets(in: desktop).isEmpty {
                let original = ((backupDictionary?[key] as? [String: Any])?["Content"]) ?? fallback
                if let original { desktop["Content"] = original }
                dictionary[key] = desktop
            } else if value is [String: Any] {
                dictionary[key] = restoringMaclandChoices(in: value, backup: backupDictionary?[key], fallback: fallback)
            }
        }
        return dictionary
    }

    // MARK: Registre

    private static func readStore() throws -> [String: Any] {
        let data = try Data(contentsOf: storeFile)
        guard let store = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return store
    }

    private static func writeStore(_ store: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
        try data.write(to: storeFile, options: .atomic)
    }

    /// Sauvegarde le registre d'origine, une seule fois, et seulement s'il ne contient pas déjà un fond macland.
    private static func backUpOnce() {
        guard !FileManager.default.fileExists(atPath: backupFile.path), selectedMaclandAsset == nil else { return }
        // Copie fidèle de l'état d'origine, relue seulement pour restaurer les choix remplacés.
        try? FileManager.default.createDirectory(at: WallpaperLibrary.directory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: storeFile, to: backupFile)
    }

    /// Remplace, partout dans l'arbre, le choix des nœuds « Desktop » (bureau et verrouillage).
    private static func replacingDesktopChoices(in node: Any, with choice: [String: Any]) -> Any? {
        guard var dictionary = node as? [String: Any] else { return node }
        for (key, value) in dictionary {
            if key == "Desktop", var desktop = value as? [String: Any], var content = desktop["Content"] as? [String: Any] {
                content["Choices"] = [choice]
                content["Shuffle"] = "$null"
                desktop["Content"] = content
                desktop["LastSet"] = Date.now
                dictionary[key] = desktop
            } else if value is [String: Any] {
                dictionary[key] = replacingDesktopChoices(in: value, with: choice)
            }
        }
        return dictionary
    }

    /// Toutes les vidéos macland choisies, où qu'elles soient dans l'arbre.
    private static func maclandAssets(in node: Any) -> [String] {
        if let list = node as? [Any] { return list.flatMap(maclandAssets(in:)) }
        guard let dictionary = node as? [String: Any] else { return [] }
        if (dictionary["Provider"] as? String) == aerialProvider, let data = dictionary["Configuration"] as? Data,
           let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let asset = configuration["assetID"] as? String, asset.hasPrefix("MACLAND-") {
            return [asset]
        }
        return dictionary.values.flatMap(maclandAssets(in:))
    }

    private static func restartAgent() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try? process.run()
    }
}
