import AVFoundation
import AppKit

enum WallpaperScaling: String, CaseIterable, Identifiable {
    /// Remplit l'écran (la vidéo peut être rognée).
    case fill
    /// Vidéo entière (bandes noires possibles).
    case fit

    var id: String { rawValue }

    var gravity: AVLayerVideoGravity { self == .fill ? .resizeAspectFill : .resizeAspect }
}

/// Fenêtre placée au niveau du fond d'écran : sous les icônes du bureau, sur tous les Spaces.
private final class DesktopWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Une vidéo qui tourne en boucle dans une couche.
private final class LoopingVideo {
    let layer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL, gravity: AVLayerVideoGravity) {
        player.isMuted = true
        // Le Mac doit pouvoir éteindre l'écran même si la vidéo tourne.
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        layer.player = player
        layer.videoGravity = gravity
    }

    #if DEBUG
    var debugStatus: String {
        "lecture=\(player.timeControlStatus == .playing) t=\(String(format: "%.2f", player.currentTime().seconds)) prête=\(layer.isReadyForDisplay)"
    }
    #endif

    func play() { player.play() }
    func pause() { player.pause() }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        layer.player = nil
    }
}

/// Affiche une vidéo en fond de bureau sur chaque écran, avec fondu entre deux vidéos.
@MainActor
final class DesktopVideoEngine {
    private var windows: [CGDirectDisplayID: DesktopWindow] = [:]
    private var screens: [CGDirectDisplayID: NSScreen] = [:]
    private var videos: [CGDirectDisplayID: LoopingVideo] = [:]
    private var currentURL: URL?
    private var observers: [NSObjectProtocol] = []
    /// Observateurs liés aux fenêtres actuelles (retirés quand elles sont recréées).
    private var windowObservers: [NSObjectProtocol] = []

    var scaling = WallpaperScaling.fill {
        didSet { videos.values.forEach { $0.layer.videoGravity = scaling.gravity } }
    }
    /// Fondu enchaîné lors d'un changement de vidéo.
    var crossfade = true
    /// Pause quand des fenêtres cachent entièrement le bureau.
    var pauseWhenCovered = true { didSet { updatePlayback() } }
    /// Pause quand une app est en plein écran sur l'écran concerné.
    var pauseInFullScreen = true { didSet { updatePlayback() } }
    /// Mise en pause imposée (batterie, session verrouillée…), en plus de la pause automatique
    /// quand le bureau est masqué.
    var isSuspended = false {
        didSet { updatePlayback() }
    }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWindows() }
        })
        // Passage en plein écran : changement d'espace ou d'app active.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    MainActor.assumeIsolated { self?.updatePlayback() }
                }
            })
        }
    }

    deinit {
        (observers + windowObservers).forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    var isShowing: Bool { currentURL != nil }

    #if DEBUG
    var debugStatus: String {
        windows.map { display, window in
            "écran \(display) niveau=\(window.level.rawValue) visible=\(window.isVisible) cadre=\(window.frame) \(videos[display]?.debugStatus ?? "-")"
        }.joined(separator: "\n")
    }
    #endif

    /// Affiche `url` (ou rien si `nil`) sur tous les écrans.
    func show(_ url: URL?) {
        #if DEBUG
        // Mesures : tout le reste de l'app tourne, sans la vidéo de bureau.
        if CommandLine.arguments.contains("--no-desktop-video") { return }
        #endif
        guard url != currentURL else { return }
        currentURL = url
        guard let url else {
            tearDown()
            return
        }
        if windows.isEmpty { rebuildWindows() }
        for (display, window) in windows {
            replaceVideo(on: display, in: window, with: url)
        }
        updatePlayback()
    }

    func tearDown() {
        removeWindowObservers()
        videos.values.forEach { $0.stop() }
        videos.removeAll()
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        screens.removeAll()
        currentURL = nil
    }

    // MARK: Fenêtres

    private func removeWindowObservers() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    private func rebuildWindows() {
        guard let url = currentURL else { return }
        removeWindowObservers()
        videos.values.forEach { $0.stop() }
        videos.removeAll()
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()

        for screen in NSScreen.screens {
            guard let display = screen.displayID else { continue }
            let window = DesktopWindow(screen: screen)
            let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.black.cgColor
            window.contentView = content
            window.orderBack(nil)
            windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePlayback() }
            })
            windows[display] = window
            screens[display] = screen
            replaceVideo(on: display, in: window, with: url, animated: false)
        }
        updatePlayback()
    }

    private func replaceVideo(on display: CGDirectDisplayID, in window: DesktopWindow, with url: URL, animated: Bool = true) {
        guard let container = window.contentView?.layer else { return }
        let next = LoopingVideo(url: url, gravity: scaling.gravity)
        next.layer.frame = container.bounds
        next.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        let previous = videos[display]
        videos[display] = next

        if animated, crossfade, let previous {
            next.layer.opacity = 0
            container.addSublayer(next.layer)
            CATransaction.begin()
            CATransaction.setAnimationDuration(1.2)
            CATransaction.setCompletionBlock { previous.stop(); previous.layer.removeFromSuperlayer() }
            next.layer.opacity = 1
            CATransaction.commit()
        } else {
            previous?.stop()
            previous?.layer.removeFromSuperlayer()
            container.addSublayer(next.layer)
        }
    }

    /// Pause selon les choix de l'utilisateur : bureau couvert par des fenêtres, app en plein écran,
    /// ou suspension imposée (batterie, session verrouillée…).
    private func updatePlayback() {
        for (display, window) in windows {
            var covered = !window.occlusionState.contains(.visible)
            #if DEBUG
            // Pour les tests : le bureau est souvent couvert de fenêtres.
            if CommandLine.arguments.contains("--ignore-occlusion") { covered = false }
            #endif
            let fullScreen = screens[display].map(FullScreenDetector.isFullScreenApp(on:)) ?? false
            // En plein écran, le bureau est forcément caché : seule l'option « plein écran » décide.
            let paused = isSuspended || (fullScreen ? pauseInFullScreen : covered && pauseWhenCovered)
            if paused { videos[display]?.pause() } else { videos[display]?.play() }
        }
    }
}
