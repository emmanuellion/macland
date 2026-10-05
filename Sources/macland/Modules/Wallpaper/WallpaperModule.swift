import AppKit
import IOKit.ps
import SwiftUI

enum LockScreenMode: String, CaseIterable, Identifiable {
    /// Image tirée de la vidéo, posée comme fond système (fonctionne partout).
    case still
    /// Vraie vidéo, jouée par macOS via son catalogue de fonds animés (macOS 26+).
    case native

    var id: String { rawValue }
}

/// Fonds d'écran vidéo : une vidéo ou une playlist sur le bureau, et une image tirée de la
/// vidéo sur l'écran de verrouillage (macOS n'y accepte pas de vidéo).
@MainActor
@Observable
final class WallpaperModule: IslandModule {
    let id = "wallpaper"
    var name: String { tr("Fonds d'écran", "Wallpapers") }
    let systemImage = "photo.on.rectangle.angled"
    var summary: String {
        tr("Vidéos en fond de bureau, seules ou en playlist, et image assortie sur l'écran de verrouillage.",
           "Video desktop wallpapers, single or in playlists, with a matching image on the lock screen.")
    }
    let tint = Color.purple
    let kind = ModuleKind.service
    let enabledByDefault = false

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "wallpaper", registering: [
        "desktopSource": "",
        "lockSource": "",
        "lockFollowsDesktop": true,
        "scaling": WallpaperScaling.fill.rawValue,
        "crossfade": true,
        "pauseOnBattery": true,
        "pauseInLowPower": true,
        "pauseWhenCovered": true,
        "pauseInFullScreen": true,
        "lockMode": (AerialCatalog.isAvailable ? LockScreenMode.native : LockScreenMode.still).rawValue,
    ])

    let library = WallpaperLibrary()

    var desktopSource: WallpaperSource { didSet { save(desktopSource, "desktopSource"); applyDesktop() } }
    var lockSource: WallpaperSource { didSet { save(lockSource, "lockSource"); applyLock() } }
    /// L'écran de verrouillage suit la vidéo du bureau.
    var lockFollowsDesktop: Bool { didSet { store.set(lockFollowsDesktop, "lockFollowsDesktop"); applyLock() } }
    var scaling: WallpaperScaling { didSet { store.set(scaling.rawValue, "scaling"); engine.scaling = scaling } }
    var crossfade: Bool { didSet { store.set(crossfade, "crossfade"); engine.crossfade = crossfade } }
    var pauseOnBattery: Bool { didSet { store.set(pauseOnBattery, "pauseOnBattery"); updateSuspension() } }
    var pauseInLowPower: Bool { didSet { store.set(pauseInLowPower, "pauseInLowPower"); updateSuspension() } }
    /// Pause quand des fenêtres cachent entièrement le bureau.
    var pauseWhenCovered: Bool { didSet { store.set(pauseWhenCovered, "pauseWhenCovered"); engine.pauseWhenCovered = pauseWhenCovered } }
    /// Pause quand une app est en plein écran.
    var pauseInFullScreen: Bool { didSet { store.set(pauseInFullScreen, "pauseInFullScreen"); engine.pauseInFullScreen = pauseInFullScreen } }
    var lockMode: LockScreenMode {
        didSet {
            store.set(lockMode.rawValue, "lockMode")
            // Changement de mode : on repart du fond d'origine puis on applique le nouveau mode.
            guard lockMode != oldValue else { return }
            restoreLockScreen()
            applyLock()
        }
    }

    /// Vidéo appliquée en mode natif (pour éviter de relancer l'agent de macOS pour rien).
    @ObservationIgnored private var nativeVideo: UUID?
    /// Erreur du mode natif, affichée dans les réglages.
    private(set) var nativeError: String?

    /// Vidéo actuellement sur le bureau (pour l'affichage dans les réglages).
    private(set) var currentDesktopVideo: UUID?
    private(set) var isPaused = false

    @ObservationIgnored private let engine = DesktopVideoEngine()
    @ObservationIgnored private var desktopRotation: Rotation?
    @ObservationIgnored private var lockRotation: Rotation?
    @ObservationIgnored private var powerTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var screenLocked = false
    @ObservationIgnored private var isRunning = false

    init() {
        desktopSource = Self.decode(store.string("desktopSource"))
        lockSource = Self.decode(store.string("lockSource"))
        lockFollowsDesktop = store.bool("lockFollowsDesktop")
        scaling = WallpaperScaling(rawValue: store.string("scaling")) ?? .fill
        crossfade = store.bool("crossfade")
        pauseOnBattery = store.bool("pauseOnBattery")
        pauseInLowPower = store.bool("pauseInLowPower")
        pauseWhenCovered = store.bool("pauseWhenCovered")
        pauseInFullScreen = store.bool("pauseInFullScreen")
        lockMode = LockScreenMode(rawValue: store.string("lockMode")) ?? .still
    }

    func expandedView() -> AnyView { AnyView(EmptyView()) }
    func settingsView() -> AnyView? { AnyView(WallpaperSettingsView(module: self)) }

    func start() {
        isRunning = true
        engine.scaling = scaling
        engine.crossfade = crossfade
        engine.pauseWhenCovered = pauseWhenCovered
        engine.pauseInFullScreen = pauseInFullScreen

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = true; self?.updateSuspension() }
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = false; self?.updateSuspension() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSuspension() }
        })
        // Branchement / débranchement du chargeur : vérifié régulièrement, c'est très léger.
        powerTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSuspension() }
        }

        applyDesktop()
        applyLock()
        updateSuspension()
    }

    func stop() {
        isRunning = false
        desktopRotation = nil
        lockRotation = nil
        powerTimer?.invalidate()
        powerTimer = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        observers.removeAll()
        cancelLockTask()
        engine.tearDown()
        currentDesktopVideo = nil
        // Module désactivé : on remet le fond d'origine. À la fermeture de l'app, on le garde.
        if !AppLifecycle.isTerminating { restoreLockScreen() }
    }

    // MARK: Bureau

    private func applyDesktop() {
        guard isRunning else { return }
        let videos = library.videos(for: desktopSource)
        desktopRotation = Rotation(videos: videos, playlist: playlist(of: desktopSource)) { [weak self] video in
            self?.showOnDesktop(video)
        }
        if videos.isEmpty {
            showOnDesktop(nil)
            if lockFollowsDesktop { restoreLockScreen() }
        }
    }

    private func showOnDesktop(_ video: WallpaperVideo?) {
        currentDesktopVideo = video?.id
        engine.show(video?.url)
        if lockFollowsDesktop, let video { setLockScreen(video) }
    }

    // MARK: Écran de verrouillage

    private func applyLock() {
        guard isRunning else { return }
        if lockFollowsDesktop {
            lockRotation = nil
            if let id = currentDesktopVideo, let video = library.video(id) {
                setLockScreen(video)
            } else {
                restoreLockScreen()
            }
            return
        }
        let videos = library.videos(for: lockSource)
        lockRotation = Rotation(videos: videos, playlist: playlist(of: lockSource)) { [weak self] video in
            self?.setLockScreen(video)
        }
        if videos.isEmpty { restoreLockScreen() }
    }

    /// Vidéos qui peuvent passer sur l'écran de verrouillage (à installer dans le catalogue de macOS).
    private var lockVideos: [WallpaperVideo] {
        library.videos(for: lockFollowsDesktop ? desktopSource : lockSource)
    }

    /// Une seule application à la fois : la précédente est annulée, et une tâche dépassée
    /// (module arrêté, autre vidéo choisie entre-temps) n'écrit plus rien chez macOS.
    @ObservationIgnored private var lockTask: Task<Void, Never>?
    @ObservationIgnored private var lockGeneration = 0

    private func cancelLockTask() {
        lockTask?.cancel()
        lockTask = nil
        lockGeneration += 1
    }

    private func setLockScreen(_ video: WallpaperVideo) {
        cancelLockTask()
        let generation = lockGeneration
        let isCurrent: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return isRunning && lockGeneration == generation && !Task.isCancelled
        }
        switch lockMode {
        case .still:
            lockTask = Task { await SystemWallpaper.apply(videoURL: video.url, id: video.id, isCurrent: isCurrent) }
        case .native:
            applyNative(video, isCurrent: isCurrent)
        }
    }

    /// Mode natif, entièrement automatique : la vidéo est ajoutée au catalogue des fonds animés
    /// de macOS puis choisie comme fond système. macOS la joue lui-même, verrouillage compris.
    private func applyNative(_ video: WallpaperVideo, isCurrent: @escaping @MainActor () -> Bool) {
        guard video.id != nativeVideo || nativeError != nil else { return }
        nativeVideo = video.id
        let videos = lockVideos
        lockTask = Task {
            do {
                if !AerialCatalog.installedVideoIDs.contains(video.id) || AerialCatalog.installedVideoIDs != Set(videos.map(\.id)) {
                    try await AerialCatalog.install(videos)
                }
                guard isCurrent() else { return }
                try SystemWallpaperChoice.select(assetID: AerialCatalog.assetID(for: video.id))
                nativeError = nil
            } catch is CancellationError {
                return
            } catch {
                if isCurrent() { nativeError = error.localizedDescription }
            }
        }
    }

    /// Remet le fond d'origine (image fixe ou vidéo native) et nettoie le catalogue de macOS.
    private func restoreLockScreen() {
        cancelLockTask()
        SystemWallpaper.restoreOriginals()
        if nativeVideo != nil || SystemWallpaperChoice.selectedMaclandAsset != nil {
            SystemWallpaperChoice.restore()
            try? AerialCatalog.uninstall()
        }
        nativeVideo = nil
    }

    // MARK: Énergie

    private func updateSuspension() {
        let onBattery: Bool = {
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
            return type == kIOPMBatteryPowerKey
        }()
        let saving = (pauseOnBattery && onBattery) || (pauseInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled)
        isPaused = screenLocked || saving
        engine.isSuspended = isPaused
    }

    // MARK: Actions

    func importVideos() {
        let panel = NSOpenPanel()
        panel.title = tr("Ajouter des vidéos", "Add videos")
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL.moviesDirectory
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        library.importVideos(panel.urls)
    }

    func removeVideo(_ id: UUID) {
        library.removeVideo(id)
        if desktopSource == .video(id) { desktopSource = .none } else { applyDesktop() }
        // La rotation du verrouillage peut contenir la vidéo supprimée : on la reconstruit.
        if lockSource == .video(id) { lockSource = .none } else if !lockFollowsDesktop { applyLock() }
    }

    func removePlaylist(_ id: UUID) {
        library.removePlaylist(id)
        if desktopSource == .playlist(id) { desktopSource = .none }
        if lockSource == .playlist(id) { lockSource = .none }
    }

    /// À appeler après la modification d'une playlist en cours d'utilisation.
    func playlistDidChange(_ id: UUID) {
        if desktopSource == .playlist(id) { applyDesktop() }
        if !lockFollowsDesktop, lockSource == .playlist(id) { applyLock() }
    }

    func sourceName(_ source: WallpaperSource) -> String {
        switch source {
        case .none: tr("Aucun", "None")
        case .video(let id): library.video(id)?.name ?? tr("Vidéo supprimée", "Deleted video")
        case .playlist(let id): library.playlist(id).map { "▶︎ \($0.name)" } ?? tr("Playlist supprimée", "Deleted playlist")
        }
    }

    // MARK: Utilitaires

    private func playlist(of source: WallpaperSource) -> WallpaperPlaylist? {
        if case .playlist(let id) = source { return library.playlist(id) }
        return nil
    }

    private func save(_ source: WallpaperSource, _ key: String) {
        let data = (try? JSONEncoder().encode(source)) ?? Data()
        store.set(String(decoding: data, as: UTF8.self), key)
    }

    private static func decode(_ text: String) -> WallpaperSource {
        guard let data = text.data(using: .utf8), let source = try? JSONDecoder().decode(WallpaperSource.self, from: data)
        else { return .none }
        return source
    }
}

/// Enchaîne les vidéos d'une playlist à intervalle régulier (ou affiche une vidéo seule).
@MainActor
private final class Rotation {
    private var order: [WallpaperVideo]
    private var index = 0
    private var timer: Timer?
    private let show: (WallpaperVideo) -> Void

    init(videos: [WallpaperVideo], playlist: WallpaperPlaylist?, show: @escaping (WallpaperVideo) -> Void) {
        self.order = playlist?.shuffle == true ? videos.shuffled() : videos
        self.show = show
        guard let first = order.first else { return }
        show(first)
        if order.count > 1, let minutes = playlist?.intervalMinutes {
            timer = Timer.scheduledTimer(withTimeInterval: max(10, minutes * 60), repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.next() }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func next() {
        index = (index + 1) % order.count
        show(order[index])
    }
}
