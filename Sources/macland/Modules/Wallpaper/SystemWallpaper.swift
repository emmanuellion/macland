import AppKit

/// Fond d'écran « système » (image fixe), celui qu'affiche l'écran de verrouillage.
///
/// macOS ne permet pas de mettre une vidéo sur l'écran de verrouillage : on y pose une image
/// extraite de la vidéo. Le fond d'origine est mémorisé pour pouvoir le remettre.
@MainActor
enum SystemWallpaper {
    private static let framesDirectory = WallpaperLibrary.directory.appending(path: "Frames", directoryHint: .isDirectory)
    private static let originalsKey = "module.wallpaper.originalDesktopImages"

    /// Applique une image extraite de la vidéo comme fond système sur tous les écrans.
    /// `isCurrent` est vérifié après l'extraction (lente) : si le module a été arrêté ou si une
    /// autre vidéo a été choisie entre-temps, rien n'est appliqué.
    static func apply(videoURL: URL, id: UUID, isCurrent: @MainActor () -> Bool = { true }) async {
        guard let frame = await WallpaperLibrary.frame(of: videoURL), isCurrent(),
              let destination = writeFrame(frame, id: id) else { return }
        rememberOriginals()
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(destination, for: screen, options: [:])
        }
    }

    /// Remet les fonds d'écran d'avant macland.
    static func restoreOriginals() {
        guard var originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let display = screen.displayID, let path = originals[String(display)] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(filePath: path), for: screen, options: [:])
            originals[String(display)] = nil
        }
        // Les écrans débranchés gardent leur fond d'origine en mémoire, pour la prochaine fois.
        if originals.isEmpty {
            UserDefaults.standard.removeObject(forKey: originalsKey)
        } else {
            UserDefaults.standard.set(originals, forKey: originalsKey)
        }
    }

    /// Mémorise le fond actuel de chaque écran, une seule fois (avant toute modification).
    private static func rememberOriginals() {
        guard UserDefaults.standard.dictionary(forKey: originalsKey) == nil else { return }
        var originals: [String: String] = [:]
        for screen in NSScreen.screens {
            if let display = screen.displayID, let url = NSWorkspace.shared.desktopImageURL(for: screen),
               !url.path.hasPrefix(framesDirectory.path) {
                originals[String(display)] = url.path
            }
        }
        UserDefaults.standard.set(originals, forKey: originalsKey)
    }

    /// Un fichier par vidéo : macOS ne recharge pas une image dont le chemin n'a pas changé.
    private static func writeFrame(_ image: CGImage, id: UUID) -> URL? {
        try? FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
        let url = framesDirectory.appending(path: "\(id.uuidString).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
