import AppKit
import SwiftUI

/// Panneau transparent, sans bordure, placé au-dessus de la barre des menus.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepte le premier clic même si l'app n'est pas active.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Gère l'île d'un écran : position de la fenêtre, survol de la souris, ouverture/fermeture.
@MainActor
final class NotchWindowController {
    /// Taille maximale réservée au panneau (doit couvrir les valeurs max des réglages + l'ombre).
    private static let panelSize = CGSize(width: 900, height: 360)
    /// Marge de tolérance autour de l'encoche pour déclencher le survol.
    private static let hoverPadding: CGFloat = 4

    let screen: NSScreen
    private let model: NotchViewModel
    private let panel: NotchPanel
    private let settings = IslandSettings.shared

    private var monitors: [Any] = []
    private var pendingAction: DispatchWorkItem?
    /// Ouverte par un raccourci : pas de fermeture au survol tant que la souris n'est pas venue dessus.
    private var openedWithoutHover = false
    private var dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount

    init(screen: NSScreen, onOpenSettings: @escaping () -> Void) {
        self.screen = screen
        model = NotchViewModel(geometry: NotchGeometry(screen: screen))
        panel = NotchPanel(contentRect: .zero)

        let hosting = FirstMouseHostingView(rootView: NotchView(model: model, onOpenSettings: onOpenSettings))
        hosting.sizingOptions = []
        panel.contentView = hosting

        updateFrame()
        panel.orderFrontRegardless()
        installMouseMonitors()
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pendingAction?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    private func updateFrame() {
        let size = Self.panelSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width,
                           height: size.height)
        panel.setFrame(frame, display: true)
    }

    // MARK: Souris

    /// Zone interactive actuelle, en coordonnées écran (origine en bas à gauche).
    ///
    /// Elle dépasse volontairement au-dessus de l'écran : tout en haut, le curseur est
    /// exactement sur `screen.frame.maxY`, que `NSRect.contains` exclut. Sans cette marge,
    /// l'île ouverte croyait la souris sortie, se refermait, puis se rouvrait en boucle.
    private var activeRect: NSRect {
        let size = model.shapeSize
        let padding = Self.hoverPadding
        return NSRect(x: screen.frame.midX - size.width / 2 - padding,
                      y: screen.frame.maxY - size.height - padding,
                      width: size.width + 2 * padding,
                      height: size.height + padding + 20)
    }

    private func installMouseMonitors() {
        let moveEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp]
        let clickEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveEvents, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved(event.type) }
        }) { monitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: moveEvents, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved(event.type) }
            return event
        }) { monitors.append(local) }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: clickEvents, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDownOutside() }
        }) { monitors.append(global) }
    }

    private func mouseMoved(_ type: NSEvent.EventType = .mouseMoved) {
        #if DEBUG
        if debugPinned { return }
        #endif
        let inside = activeRect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside

        if inside {
            openedWithoutHover = false
            if model.isExpanded {
                cancelPending()
            } else if type == .leftMouseDragged, isDraggingFiles, let receiver = ModuleRegistry.shared.fileDropReceiver {
                // Un fichier glissé vers l'encoche ouvre directement la page qui le reçoit.
                cancelPending()
                model.expand(page: receiver.kind == .page ? receiver.id : nil)
            } else if let activity = model.activity, activity.isInteractive {
                // Activité manipulable (HUD) : on la garde affichée au lieu de déplier l'île.
                cancelPending()
                ActivityCenter.shared.extend(activity.id)
            } else if settings.expandTrigger == .hover, type == .mouseMoved, pendingAction == nil {
                schedule(after: settings.hoverDelay) { [weak self] in self?.model.expand() }
            }
        } else if model.isExpanded {
            // Pas de fermeture tant qu'un glisser-déposer est en cours.
            let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
            if !buttonDown, !openedWithoutHover, pendingAction == nil {
                schedule(after: settings.collapseDelay) { [weak self] in self?.model.collapse() }
            }
        } else {
            cancelPending()
        }
    }

    /// Vrai si le glisser en cours transporte des fichiers (le presse-papiers de glisser a changé depuis le clic).
    private var isDraggingFiles: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.changeCount != dragChangeCountAtMouseDown
            && pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    // MARK: Commandes

    var containsMouse: Bool { screen.frame.contains(NSEvent.mouseLocation) }

    /// Ouvre l'île sur une page ; la referme si cette page est déjà affichée.
    func open(page: String) {
        cancelPending()
        if model.isExpanded && model.selectedPage == page {
            collapse()
            return
        }
        openedWithoutHover = !activeRect.contains(NSEvent.mouseLocation)
        model.expand(page: page)
    }

    func collapse() {
        cancelPending()
        openedWithoutHover = false
        model.collapse()
        panel.ignoresMouseEvents = !activeRect.contains(NSEvent.mouseLocation)
    }

    private func mouseDownOutside() {
        dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        guard model.isExpanded, !activeRect.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    private func schedule(after delay: Double, _ action: @escaping @MainActor () -> Void) {
        cancelPending()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingAction = nil
                action()
                self?.mouseMoved()
            }
        }
        pendingAction = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        pendingAction?.cancel()
        pendingAction = nil
    }

    #if DEBUG
    private var debugPinned = false
    func debugExpand(page: String? = nil) {
        debugPinned = true
        model.expand(page: page)
    }
    func debugCollapse() { model.collapse() }

    /// `point` en coordonnées SwiftUI globales (origine en haut à gauche du panneau).
    func debugSendMouse(_ type: NSEvent.EventType, at point: CGPoint) {
        panel.ignoresMouseEvents = false
        let location = NSPoint(x: point.x, y: panel.frame.height - point.y)
        guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: panel.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        else { return }
        NSApp.sendEvent(event)
    }
    func debugCapture(name: String) { DebugSnapshots.capture(panel, name: name) }
    #endif
}
