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
        BatteryModule(),
        ClipboardModule(),
        ShelfModule(),
        SystemHUDModule(),
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

    /// Position (1-based) d'un module parmi ceux du même type (widgets ou pages), et nombre total.
    func position(of module: any IslandModule) -> (index: Int, count: Int)? {
        let sameKind = orderedModules.filter { $0.kind == module.kind }
        guard let index = sameKind.firstIndex(where: { $0.id == module.id }) else { return nil }
        return (index + 1, sameKind.count)
    }

    /// Échange un module avec son voisin du même type (-1 = vers la gauche, +1 = vers la droite).
    func move(_ module: any IslandModule, by offset: Int) {
        var ids = orderedModules.map(\.id)
        let sameKindIDs = orderedModules.filter { $0.kind == module.kind }.map(\.id)
        guard let position = sameKindIDs.firstIndex(of: module.id),
              sameKindIDs.indices.contains(position + offset),
              let from = ids.firstIndex(of: module.id),
              let to = ids.firstIndex(of: sameKindIDs[position + offset])
        else { return }
        ids.swapAt(from, to)
        settings.moduleOrder = ids
    }
}
