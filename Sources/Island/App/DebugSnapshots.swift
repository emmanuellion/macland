#if DEBUG
import AppKit

/// Développement uniquement : `Island --snapshots <dossier>` capture les fenêtres de l'app en PNG
/// (une app peut capturer ses propres fenêtres sans permission d'enregistrement d'écran).
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshots"), args.indices.contains(index + 1) else { return nil }
        return URL(filePath: args[index + 1], directoryHint: .isDirectory)
    }

    static func capture(_ window: NSWindow?, name: String) {
        guard let directory, let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }
}
#endif
