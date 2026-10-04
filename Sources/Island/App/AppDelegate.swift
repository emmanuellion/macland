import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = IslandSettings.shared
    private var notchControllers: [NotchWindowController] = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ModuleRegistry.shared.startEnabledModules()
        terminateCleanlyOnSignals()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildNotches() }
        }

        NotificationCenter.default.addObserver(forName: IslandCommands.openPageNotification, object: nil, queue: .main) { [weak self] note in
            guard let page = note.object as? String else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                // L'écran sous la souris, sinon celui avec l'encoche.
                let target = self.notchControllers.first(where: \.containsMouse) ?? self.notchControllers.first
                target?.open(page: page)
            }
        }
        NotificationCenter.default.addObserver(forName: IslandCommands.collapseNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notchControllers.forEach { $0.collapse() } }
        }

        observe { [weak self] in
            guard let self else { return }
            _ = settings.showOnScreensWithoutNotch
            rebuildNotches()
        }
        observe { [weak self] in
            guard let self else { return }
            // La langue est lue ici pour reconstruire le menu quand elle change.
            _ = settings.isFrench
            updateStatusItem(visible: settings.showMenuBarIcon)
        }

        #if DEBUG
        // Les tests utilisent aussi --snapshots <dossier> pour leurs captures.
        let arguments = CommandLine.arguments
        applyDebugOverrides(arguments)
        if arguments.contains("--test-scrub") {
            runScrubTest()
        } else if arguments.contains("--test-pause") {
            runPauseTest()
        } else if arguments.contains("--record") {
            runRecording()
        } else if arguments.contains("--test-files") {
            runFileActionsTest()
        } else if arguments.contains("--test-system") {
            runSystemTest()
        } else if DebugSnapshots.directory != nil {
            runSnapshots()
        }
        #endif
    }

    #if DEBUG
    /// Simule un glisser sur la barre de progression (événements souris envoyés à l'app elle-même).
    private func runScrubTest() {
        guard let controller = notchControllers.first,
              let module = ModuleRegistry.shared.module(id: "nowPlaying") as? NowPlayingModule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            controller.debugExpand()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            let frame = module.debugProgressFrame
            debugLog("progress frame (global) = \(frame)")
            let steps: [(NSEvent.EventType, Double)] = [(.leftMouseDown, 0.2), (.leftMouseDragged, 0.35), (.leftMouseDragged, 0.5),
                                                        (.leftMouseDragged, 0.7), (.leftMouseUp, 0.7)]
            for (index, (type, fraction)) in steps.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(index)) {
                    controller.debugSendMouse(type, at: CGPoint(x: frame.minX + frame.width * fraction, y: frame.midY))
                    if index == 3 { controller.debugCapture(name: "scrub-dragging") }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
            controller.debugCapture(name: "scrub-after")
            NSApp.terminate(nil)
        }
    }

    /// Lance la lecture 4 s puis met en pause ; le journal montre la position vue par le module.
    private func runPauseTest() {
        guard let module = ModuleRegistry.shared.module(id: "nowPlaying") as? NowPlayingModule else { return }
        let report = { (label: String) in
            if let info = module.info {
                debugLog("\(label): playing=\(info.isPlaying) position=\(String(format: "%.2f", info.elapsed(at: .now)))")
            }
        }
        for tick in 0..<40 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + 0.25 * Double(tick)) { report("t+\(String(format: "%.2f", 1 + 0.25 * Double(tick)))") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { debugLog("→ play"); module.debugSend(.play) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { debugLog("→ pause"); module.debugSend(.pause) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 11) { NSApp.terminate(nil) }
    }

    /// Lit volume, luminosité, caméra, micro, et capture les deux styles de HUD.
    private func runSystemTest() {
        debugLog("volume=\(AudioDevices.volume.map { String($0) } ?? "nil") muted=\(AudioDevices.isMuted) settable=\(AudioDevices.canSetVolume)")
        debugLog("sorties=\(AudioDevices.outputDevices.map(\.name)) défaut=\(AudioDevices.defaultOutput.map { String($0) } ?? "nil")")
        debugLog("luminosité dispo=\(DisplayBrightness.isAvailable) valeur=\(DisplayBrightness.value.map { String($0) } ?? "nil")")
        debugLog("caméra active=\(CameraUsage.isAnyCameraRunning) micro=\(AudioDevices.appsUsingMicrophone)")
        debugLog("accessibilité=\(AXIsProcessTrusted())")
        guard let hud = ModuleRegistry.shared.module(id: "hud") as? SystemHUDModule,
              let controller = notchControllers.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            hud.style = .extended
            hud.showHUD(.volume)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            controller.debugCapture(name: "hud-extended")
            hud.style = .compact
            hud.showHUD(.brightness)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            controller.debugCapture(name: "hud-compact")
            hud.style = .extended
            NSApp.terminate(nil)
        }
    }

    /// Compresse et convertit des fichiers jetables dans un dossier temporaire.
    private func runFileActionsTest() {
        Task {
            let folder = FileManager.default.temporaryDirectory.appending(path: "island-test-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let text = folder.appending(path: "note.txt")
            try? "bonjour".write(to: text, atomically: true, encoding: .utf8)
            let image = folder.appending(path: "image.png")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
            try? bitmap.representation(using: .png, properties: [:])?.write(to: image)
            do {
                let zip1 = try await FileActions.zip([text])
                debugLog("zip 1 → \(zip1.lastPathComponent)")
                let zip2 = try await FileActions.zip([text, image])
                debugLog("zip 2 → \(zip2.lastPathComponent)")
                let jpeg = try await FileActions.convert(image, to: .jpeg)
                debugLog("jpeg → \(jpeg.lastPathComponent)")
                let heic = try await FileActions.convert(image, to: .heic)
                debugLog("heic → \(heic.lastPathComponent)")
                debugLog("isImage png=\(FileActions.isImage(image)) txt=\(FileActions.isImage(text))")
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.sorted() ?? []
                debugLog("dossier : \(names)")
            } catch {
                debugLog("ERREUR \(error)")
            }
            try? FileManager.default.removeItem(at: folder)
            NSApp.terminate(nil)
        }
    }

    /// --island-color <couleur>, --language <langue> : réglages forcés le temps d'une capture,
    /// remis à leur valeur précédente à la fermeture.
    private func applyDebugOverrides(_ arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let previousColor = settings.islandColor
        let previousLanguage = settings.language
        if let color = value("--island-color").flatMap(IslandColor.init(rawValue:)) { settings.islandColor = color }
        if let language = value("--language").flatMap(AppLanguage.init(rawValue:)) { settings.language = language }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                IslandSettings.shared.islandColor = previousColor
                IslandSettings.shared.language = previousLanguage
            }
        }
    }

    /// Images et GIF du README : une séquence scénarisée, filmée image par image (20 i/s).
    private func runRecording() {
        guard let directory = DebugSnapshots.directory, let controller = notchControllers.first,
              let hud = ModuleRegistry.shared.module(id: "hud") as? SystemHUDModule else { return }
        var frames: [CGImage] = []
        let recorder = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                if let frame = controller.debugMediaFrame() { frames.append(DebugMedia.downscaled(frame, by: 2)) }
            }
        }
        let still = { (name: String) in
            if let frame = controller.debugMediaFrame() {
                DebugMedia.writePNG(frame, to: directory.appending(path: "\(name).png"))
            }
        }
        let steps: [(Double, () -> Void)] = [
            (1.0, { controller.debugExpand(page: NotchViewModel.homePage) }),
            (2.4, { still("home") }),
            (2.8, { controller.debugSelect(page: "clipboard") }),
            (3.6, { still("clipboard") }),
            (4.0, { controller.debugSelect(page: "controls") }),
            (4.8, { still("controls") }),
            (5.2, { controller.debugSelect(page: "shelf") }),
            (6.0, { still("shelf") }),
            (6.4, { controller.debugSelect(page: NotchViewModel.homePage) }),
            (7.4, { controller.debugCollapse() }),
            (8.4, { hud.showHUD(.brightness) }),
            (9.0, { still("hud") }),
            (10.2, { recorder.invalidate() }),
        ]
        for (time, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { action() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
            DebugMedia.writeGIF(frames, delay: 0.05, to: directory.appending(path: "demo.gif"))
            debugLog("GIF : \(frames.count) images")
            NSApp.terminate(nil)
        }
    }

    private func runSnapshots() {
        let pages: [(String, SettingsPage)] = [("general", .general), ("appearance", .appearance), ("activities", .activities)]
            + ModuleRegistry.shared.allModules.map { ("module-\($0.id)", .module($0.id)) }
        openSettings()
        for (index, (name, page)) in pages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(index)) {
                SettingsNavigation.shared.selection = page
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(index) + 0.5) { [weak self] in
                DebugSnapshots.capture(self?.settingsWindow, name: "settings-\(name)")
            }
        }
        let end = 0.6 * Double(pages.count) + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + end) { [weak self] in
            self?.notchControllers.first?.debugExpand()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + end + 1) { [weak self] in
            self?.notchControllers.first?.debugCapture(name: "notch-home")
            self?.notchControllers.first?.debugExpand(page: "clipboard")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + end + 2) { [weak self] in
            self?.notchControllers.first?.debugCapture(name: "notch-clipboard")
            self?.notchControllers.first?.debugExpand(page: "controls")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + end + 2.6) { [weak self] in
            self?.notchControllers.first?.debugCapture(name: "notch-controls")
            self?.notchControllers.first?.debugCollapse()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + end + 3) { [weak self] in
            self?.notchControllers.first?.debugCapture(name: "notch-collapsed")
            NSApp.terminate(nil)
        }
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        // Arrête notamment le processus de lecture en cours, qui sinon survivrait à l'app.
        ModuleRegistry.shared.enabledModules.forEach { $0.stop() }
    }

    /// Relancer l'app (double-clic dans le Finder) rouvre les réglages : utile si l'icône est masquée.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Îles

    private func rebuildNotches() {
        notchControllers.forEach { $0.close() }
        let screens = NSScreen.screens.filter { $0.hasNotch || settings.showOnScreensWithoutNotch }
        notchControllers = screens.map { NotchWindowController(screen: $0, onOpenSettings: { [weak self] in self?.openSettings() }) }
    }

    // MARK: Barre des menus

    private func updateStatusItem(visible: Bool) {
        if !visible {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Island")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: tr("Réglages…", "Settings…"), action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Quitter Island", "Quit Island"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettingsAction() { openSettings() }

    // MARK: Réglages

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = tr("Réglages d'Island", "Island Settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 980, height: 700))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// `kill`/`pkill` envoie SIGTERM, qui ne passe pas par `applicationWillTerminate` : on le redirige.
    private var signalSources: [DispatchSourceSignal] = []

    private func terminateCleanlyOnSignals() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Observation

    /// Réexécute `apply` à chaque changement d'une propriété observable lue à l'intérieur.
    private func observe(_ apply: @escaping @MainActor () -> Void) {
        withObservationTracking {
            apply()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.observe(apply) }
            }
        }
    }
}
