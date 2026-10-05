import AppKit

/// Détecte si une app est en plein écran sur un écran donné.
enum FullScreenDetector {
    /// Une fenêtre d'une autre app couvre-t-elle tout l'écran (barre des menus comprise) ?
    /// Seules la taille et la position des fenêtres sont lues : aucune permission requise.
    static func isFullScreenApp(on screen: NSScreen) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return false }
        // Coordonnées CoreGraphics : origine en haut à gauche de l'écran principal.
        let target = CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // La barre des menus disparaît en plein écran ; une fenêtre simplement agrandie la laisse
        // visible. Sans ce test, une fenêtre agrandie sous l'encoche passerait pour du plein écran.
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let menuBarVisible = windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == menuBarLevel,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return false }
            return abs(bounds.minY - target.minY) < 1 && bounds.minX < target.maxX && bounds.maxX > target.minX
        }
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return false }
            // Sur un écran à encoche, le plein écran commence sous la caméra : fenêtre plus courte
            // de la hauteur de l'encoche, décalée d'autant vers le bas.
            let notch = screen.safeAreaInsets.top
            let matchesWidth = abs(bounds.width - target.width) < 1 && abs(bounds.minX - target.minX) < 1
            let fullHeight = abs(bounds.height - target.height) < 1 && abs(bounds.minY - target.minY) < 1
            let belowNotch = notch > 0 && !menuBarVisible && abs(bounds.height - (target.height - notch)) < 1
                && abs(bounds.minY - (target.minY + notch)) < 1
            return matchesWidth && (fullHeight || belowNotch)
        }
    }
}
