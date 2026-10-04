import AppKit

// Avant tout accès aux réglages : reprend les données de l'ancien nom de l'app.
LegacyMigration.run()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Pas d'icône dans le Dock : l'app vit dans l'encoche et la barre des menus.
    app.setActivationPolicy(.accessory)
    app.run()
}
