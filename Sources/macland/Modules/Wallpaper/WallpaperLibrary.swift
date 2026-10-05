import AVFoundation
import AppKit

/// Une vidéo de la bibliothèque. Le fichier est référencé (pas copié) : les vidéos pèsent lourd.
struct WallpaperVideo: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    /// Retrouve le fichier s'il a été déplacé.
    var bookmark: Data?
}

/// Plusieurs vidéos qui s'enchaînent à intervalle régulier.
struct WallpaperPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var videoIDs: [UUID]
    /// Durée d'affichage de chaque vidéo, en minutes.
    var intervalMinutes: Double
    var shuffle: Bool
}

/// Ce qu'affiche un écran (bureau ou verrouillage).
enum WallpaperSource: Codable, Equatable, Hashable {
    case none
    case video(UUID)
    case playlist(UUID)
}

/// Bibliothèque persistée dans Application Support/macland/Wallpapers/library.json.
@MainActor
@Observable
final class WallpaperLibrary {
    private(set) var videos: [WallpaperVideo] = []
    private(set) var playlists: [WallpaperPlaylist] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]

    static let directory = URL.applicationSupportDirectory.appending(path: "macland/Wallpapers", directoryHint: .isDirectory)
    private static let indexFile = directory.appending(path: "library.json")

    private struct Snapshot: Codable {
        var videos: [WallpaperVideo]
        var playlists: [WallpaperPlaylist]
    }

    init() {
        load()
    }

    // MARK: Vidéos

    func video(_ id: UUID) -> WallpaperVideo? { videos.first { $0.id == id } }
    func playlist(_ id: UUID) -> WallpaperPlaylist? { playlists.first { $0.id == id } }

    func importVideos(_ urls: [URL]) {
        for url in urls where !videos.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            let video = WallpaperVideo(id: UUID(), name: url.deletingPathExtension().lastPathComponent,
                                       url: url, bookmark: try? url.bookmarkData())
            videos.append(video)
            makeThumbnail(for: video)
        }
        save()
    }

    func removeVideo(_ id: UUID) {
        videos.removeAll { $0.id == id }
        thumbnails[id] = nil
        for index in playlists.indices { playlists[index].videoIDs.removeAll { $0 == id } }
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].name = name
        save()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(named name: String) -> WallpaperPlaylist {
        let playlist = WallpaperPlaylist(id: UUID(), name: name, videoIDs: [], intervalMinutes: 30, shuffle: false)
        playlists.append(playlist)
        save()
        return playlist
    }

    func updatePlaylist(_ playlist: WallpaperPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index] = playlist
        save()
    }

    func removePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    /// Vidéos d'une source, dans l'ordre de lecture.
    func videos(for source: WallpaperSource) -> [WallpaperVideo] {
        switch source {
        case .none: []
        case .video(let id): video(id).map { [$0] } ?? []
        case .playlist(let id): playlist(id)?.videoIDs.compactMap(video) ?? []
        }
    }

    // MARK: Vignettes

    private func makeThumbnail(for video: WallpaperVideo) {
        let url = video.url
        Task {
            guard let image = await Self.frame(of: url, maxSize: CGSize(width: 320, height: 200)) else { return }
            thumbnails[video.id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    /// Image extraite de la vidéo (à 10 % de sa durée, pour éviter un premier plan noir).
    nonisolated static func frame(of url: URL, maxSize: CGSize? = nil) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maxSize { generator.maximumSize = maxSize }
        let duration = (try? await asset.load(.duration)) ?? .zero
        let time = duration.seconds.isFinite && duration.seconds > 0
            ? CMTime(seconds: duration.seconds * 0.1, preferredTimescale: 600) : .zero
        return try? await generator.image(at: time).image
    }

    // MARK: Persistance

    private func save() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(Snapshot(videos: videos, playlists: playlists)).write(to: Self.indexFile)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexFile),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        videos = snapshot.videos.map { video in
            var video = video
            if let bookmark = video.bookmark {
                var stale = false
                if let resolved = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) {
                    video.url = resolved
                    if stale { video.bookmark = try? resolved.bookmarkData() }
                }
            }
            return video
        }
        playlists = snapshot.playlists
        videos.forEach(makeThumbnail)
    }
}
