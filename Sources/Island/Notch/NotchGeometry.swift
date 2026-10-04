import AppKit

/// Dimensions de l'encoche (réelle ou simulée) d'un écran.
struct NotchGeometry: Equatable {
    var size: CGSize
    var hasPhysicalNotch: Bool

    /// Largeur utilisée sur les écrans sans encoche.
    static let fallbackWidth: CGFloat = 185

    init(screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            size = CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            hasPhysicalNotch = true
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            size = CGSize(width: Self.fallbackWidth, height: menuBarHeight > 0 ? menuBarHeight : 24)
            hasPhysicalNotch = false
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }
}
