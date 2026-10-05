import SwiftUI

/// Liste de tous les modules connus, avec leur ordre et leur état d'activation.
@MainActor
@Observable
final class ModuleRegistry {
    static let shared = ModuleRegistry()

    @ObservationIgnored private let settings = IslandSettings.shared

    /// Tous les modules disponibles, dans l'ordre par défaut.
    let allModules: [any IslandModule] = [
        NowPlayingModule(),
        ClockModule(),
        CalendarModule(),
        WeatherModule(),
        BatteryModule(),
        ClipboardModule(),
        ShelfModule(),
        ControlsModule(),
        SystemHUDModule(),
        AirPodsModule(),
        WallpaperModule(),
        PrivacyIndicatorModule(),
    ]

    /// Modules dans l'ordre choisi par l'utilisateur (les nouveaux modules sont ajoutés à la fin).
    var orderedModules: [any IslandModule] {
        let byID = Dictionary(uniqueKeysWithValues: allModules.map { ($0.id, $0) })
        let known = settings.moduleOrder.compactMap { byID[$0] }
        let missing = allModules.filter { !settings.moduleOrder.contains($0.id) }
        return known + missing
    }

    var enabledModules: [any IslandModule] {
        orderedModules.filter(isEnabled)
    }

    /// Widgets actifs de la page d'accueil, dans l'ordre d'affichage.
    var enabledWidgets: [any IslandModule] {
        enabledModules.filter { $0.kind == .widget && $0.isVisibleInHome }
    }

    /// Modules actifs ayant leur propre page.
    var enabledPages: [any IslandModule] {
        enabledModules.filter { $0.kind == .page }
    }

    /// Module actif qui reçoit les fichiers déposés sur l'encoche, s'il y en a un.
    var fileDropReceiver: (any FileDropReceiving)? {
        enabledModules.lazy.compactMap { $0 as? any FileDropReceiving }.first
    }

    private init() {}

    func module(id: String) -> (any IslandModule)? {
        allModules.first { $0.id == id }
    }

    func startEnabledModules() {
        enabledModules.forEach { $0.start() }
    }

    func isEnabled(_ module: any IslandModule) -> Bool {
        settings.moduleEnabled[module.id] ?? module.enabledByDefault
    }

    func setEnabled(_ enabled: Bool, for module: any IslandModule) {
        guard enabled != isEnabled(module) else { return }
        settings.moduleEnabled[module.id] = enabled
        enabled ? module.start() : module.stop()
    }

    /// Place le module `id` juste avant `targetID` (glisser-déposer dans la page Disposition).
    func move(_ id: String, before targetID: String) {
        guard id != targetID else { return }
        var ids = orderedModules.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        ids.remove(at: from)
        guard let to = ids.firstIndex(of: targetID) else { return }
        ids.insert(id, at: to)
        settings.moduleOrder = ids
    }

    /// Place le module `id` en dernier parmi ceux de son type.
    func moveToEnd(_ id: String) {
        guard let module = module(id: id) else { return }
        var ids = orderedModules.map(\.id)
        ids.removeAll { $0 == id }
        let lastOfKind = ids.lastIndex { self.module(id: $0)?.kind == module.kind } ?? (ids.count - 1)
        ids.insert(id, at: min(lastOfKind + 1, ids.count))
        settings.moduleOrder = ids
    }
}
