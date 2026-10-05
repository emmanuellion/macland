import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Actions rapides sur les fichiers de l'étagère. Le résultat est écrit à côté de l'original
/// (ou dans Téléchargements si ce dossier n'est pas modifiable).
enum FileActions {
    enum ImageFormat: String, CaseIterable {
        case jpeg, png, heic

        var label: String { rawValue.uppercased() }
        var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png: .png
            case .heic: .heic
            }
        }
    }

    static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) ?? false
    }

    /// Compresse un ou plusieurs fichiers en .zip.
    static func zip(_ urls: [URL]) async throws -> URL {
        guard let first = urls.first else { throw CocoaError(.fileNoSuchFile) }
        let baseName = urls.count == 1 ? first.lastPathComponent : "Archive"
        let destination = availableURL(in: outputFolder(near: first), name: baseName, extension: "zip")

        if urls.count == 1 {
            try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, destination.path])
        } else {
            // ditto ne prend qu'une source : on rassemble les fichiers dans un dossier temporaire.
            let staging = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "Archive")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
            for url in urls {
                try FileManager.default.copyItem(at: url, to: staging.appending(path: url.lastPathComponent))
            }
            try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, destination.path])
        }
        return destination
    }

    static func convert(_ url: URL, to format: ImageFormat) async throws -> URL {
        let destination = availableURL(in: outputFolder(near: url), name: url.deletingPathExtension().lastPathComponent,
                                       extension: format.type.preferredFilenameExtension ?? format.rawValue)
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let output = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil)
            else { throw CocoaError(.fileReadCorruptFile) }
            CGImageDestinationAddImageFromSource(output, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
        }.value
        return destination
    }

    static func copyToPasteboard(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    // MARK: Utilitaires

    /// À côté de l'original, sauf s'il est dans le dossier privé de l'étagère (mode copie) :
    /// le résultat serait supprimé avec la copie. Téléchargements sinon.
    private static func outputFolder(near url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let shelfFolder = URL.applicationSupportDirectory.appending(path: "macland").standardizedFileURL.path
        if folder.standardizedFileURL.path.hasPrefix(shelfFolder) { return URL.downloadsDirectory }
        return FileManager.default.isWritableFile(atPath: folder.path) ? folder : URL.downloadsDirectory
    }

    /// « Photo.jpg », puis « Photo 2.jpg », « Photo 3.jpg »… si le nom est pris.
    private static func availableURL(in folder: URL, name: String, extension ext: String) -> URL {
        var candidate = folder.appending(path: "\(name).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(name) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(filePath: tool)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
