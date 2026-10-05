import AVFoundation
import AppKit

/// Vidéos sur l'écran de verrouillage via le catalogue « Aerials » de macOS (macOS 26+).
///
/// Les fonds animés d'Apple sont décrits dans ~/Library/Application Support/com.apple.wallpaper/
/// aerials/manifest/entries.json (dossier de l'utilisateur, pas besoin de droits admin). On y
/// ajoute une catégorie « macland » avec nos vidéos : elle apparaît dans Réglages › Fond d'écran,
/// et c'est macOS lui-même qui joue la vidéo, y compris sur l'écran de verrouillage.
///
/// Le catalogue est retéléchargé quand macOS se met à jour : il faut alors réinstaller.
@MainActor
enum AerialCatalog {
    static let categoryID = "macland"
    private static let subcategoryID = "macland-videos"
    private static let idPrefix = "MACLAND-"

    private static let root = URL.homeDirectory.appending(path: "Library/Application Support/com.apple.wallpaper/aerials",
                                                          directoryHint: .isDirectory)
    private static let entriesFile = root.appending(path: "manifest/entries.json")
    private static let videosDirectory = root.appending(path: "videos", directoryHint: .isDirectory)
    private static let thumbnailsDirectory = root.appending(path: "thumbnails", directoryHint: .isDirectory)
    /// Copie du catalogue d'origine, gardée chez nous avant toute modification.
    private static let backupFile = WallpaperLibrary.directory.appending(path: "entries.json.backup")

    enum Failure: LocalizedError {
        case catalogMissing, catalogUnreadable, exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .catalogMissing:
                tr("Catalogue des fonds animés introuvable (macOS 26 ou plus récent requis).",
                   "Animated wallpaper catalog not found (macOS 26 or later required).")
            case .catalogUnreadable:
                tr("Catalogue des fonds animés illisible.", "Animated wallpaper catalog is unreadable.")
            case .exportFailed(let name):
                tr("Impossible de préparer « \(name) ».", "Couldn't prepare “\(name)”.")
            }
        }
    }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: entriesFile.path) }

    /// Identifiants des vidéos actuellement installées dans le catalogue.
    static var installedVideoIDs: Set<UUID> {
        guard let catalog = try? readCatalog(), let assets = catalog["assets"] as? [[String: Any]] else { return [] }
        return Set(assets.compactMap { asset in
            (asset["id"] as? String).flatMap { $0.hasPrefix(idPrefix) ? UUID(uuidString: String($0.dropFirst(idPrefix.count))) : nil }
        })
    }

    /// Installe (ou remplace) les vidéos de macland dans le catalogue, puis relance l'agent.
    static func install(_ videos: [WallpaperVideo]) async throws {
        guard isAvailable else { throw Failure.catalogMissing }
        var catalog = try readCatalog()
        backUpOnce()

        var assets = (catalog["assets"] as? [[String: Any]] ?? []).filter { !isOurs($0["id"]) }
        var categories = (catalog["categories"] as? [[String: Any]] ?? []).filter { ($0["id"] as? String) != categoryID }
        removeOurFiles(keeping: Set(videos.map(assetID)))

        for (index, video) in videos.enumerated() {
            let id = assetID(video)
            let videoURL = videosDirectory.appending(path: "\(id).mov")
            let thumbnailURL = thumbnailsDirectory.appending(path: "\(id).png")
            if !FileManager.default.fileExists(atPath: videoURL.path) {
                try await exportMovie(from: video.url, to: videoURL, name: video.name)
            }
            if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
                await writeThumbnail(of: video.url, to: thumbnailURL)
            }
            assets.append([
                "id": id,
                "accessibilityLabel": video.name,
                "localizedNameKey": video.name,
                "shotID": "MACLAND_\(index)",
                "categories": [categoryID],
                "subcategories": [subcategoryID],
                "includeInShuffle": true,
                "showInTopLevel": true,
                "preferredOrder": index,
                "pointsOfInterest": [String: String](),
                "previewImage": thumbnailURL.absoluteString,
                "url-4K-SDR-240FPS": videoURL.absoluteString,
                "videoGravity": "resize",
            ])
        }

        if let first = videos.first {
            let preview = thumbnailsDirectory.appending(path: "\(assetID(first)).png").absoluteString
            categories.insert([
                "id": categoryID,
                "localizedNameKey": "macland",
                "localizedDescriptionKey": "macland",
                "preferredOrder": -1,
                "previewImage": preview,
                "representativeAssetID": assetID(first),
                "subcategories": [[
                    "id": subcategoryID,
                    "localizedNameKey": "macland",
                    "localizedDescriptionKey": "macland",
                    "preferredOrder": 0,
                    "previewImage": preview,
                    "representativeAssetID": assetID(first),
                    "combineVariants": false,
                ]],
            ], at: 0)
        }

        // Annulé pendant les exports (module arrêté, autre choix) : on ne touche pas au catalogue.
        try Task.checkCancellation()
        catalog["assets"] = assets
        catalog["categories"] = categories
        try writeCatalog(catalog)
        restartAgent()
    }

    /// Retire tout ce que macland a ajouté au catalogue.
    static func uninstall() throws {
        guard isAvailable else { return }
        var catalog = try readCatalog()
        catalog["assets"] = (catalog["assets"] as? [[String: Any]] ?? []).filter { !isOurs($0["id"]) }
        catalog["categories"] = (catalog["categories"] as? [[String: Any]] ?? []).filter { ($0["id"] as? String) != categoryID }
        try writeCatalog(catalog)
        removeOurFiles(keeping: [])
        restartAgent()
    }

    static func openWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Catalogue

    private static func readCatalog() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: entriesFile) else { throw Failure.catalogMissing }
        guard let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.catalogUnreadable }
        return catalog
    }

    /// Écriture atomique : un catalogue à moitié écrit casserait les fonds d'écran de macOS.
    private static func writeCatalog(_ catalog: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: catalog, options: [.withoutEscapingSlashes])
        try data.write(to: entriesFile, options: .atomic)
    }

    private static func backUpOnce() {
        guard !FileManager.default.fileExists(atPath: backupFile.path) else { return }
        try? FileManager.default.createDirectory(at: WallpaperLibrary.directory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: entriesFile, to: backupFile)
    }

    private static func assetID(_ video: WallpaperVideo) -> String { assetID(for: video.id) }

    /// Identifiant de la vidéo dans le catalogue de macOS.
    static func assetID(for id: UUID) -> String { idPrefix + id.uuidString }

    private static func isOurs(_ id: Any?) -> Bool { (id as? String)?.hasPrefix(idPrefix) ?? false }

    private static func removeOurFiles(keeping kept: Set<String>) {
        for directory in [videosDirectory, thumbnailsDirectory] {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for file in files where file.hasPrefix(idPrefix) && !kept.contains((file as NSString).deletingPathExtension) {
                try? FileManager.default.removeItem(at: directory.appending(path: file))
            }
        }
    }

    // MARK: Fichiers

    /// Les fonds d'Apple sont des .mov : on réemballe la vidéo sans la réencoder.
    private static func exportMovie(from source: URL, to destination: URL, name: String) async throws {
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw Failure.exportFailed(name)
        }
        // Export dans un fichier temporaire, déplacé seulement une fois complet : un export
        // interrompu ne doit pas laisser un .mov partiel que l'on prendrait pour une vidéo prête.
        let temporary = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        do {
            try await session.export(to: temporary, as: .mov)
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: temporary)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw Failure.exportFailed(name)
        }
    }

    private static func writeThumbnail(of video: URL, to destination: URL) async {
        guard let frame = await WallpaperLibrary.frame(of: video, maxSize: CGSize(width: 1280, height: 720)) else { return }
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        if let data = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) {
            try? data.write(to: destination)
        }
    }

    /// L'agent des fonds d'écran relit le catalogue en redémarrant (launchd le relance aussitôt).
    private static func restartAgent() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent", "WallpaperAerialsExtension"]
        try? process.run()
    }
}
