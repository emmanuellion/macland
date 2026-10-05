import SwiftUI
import UniformTypeIdentifiers

/// Vue d'ensemble de l'île : on y voit les onglets et les widgets de l'accueil dans leur ordre réel.
/// Glisser pour réordonner, cliquer pour activer ou désactiver. Les modules désactivés sont grisés.
struct LayoutPage: View {
    private let registry = ModuleRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PageHeader(tr("Disposition", "Layout"),
                       subtitle: tr("Glisse les éléments pour changer leur ordre, clique pour les activer ou les désactiver.",
                                    "Drag items to reorder them, click to turn them on or off."),
                       systemImage: "rectangle.3.group.fill", tint: .indigo)

            IslandLayoutPreview()

            HStack(spacing: 18) {
                Legend(enabled: true, text: tr("Activé", "On"))
                Legend(enabled: false, text: tr("Désactivé", "Off"))
                Spacer()
                Label(tr("Clic droit : réglages du module", "Right-click: module settings"), systemImage: "contextualmenu.and.cursorarrow")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.top, -16)

            ChipSection(title: tr("Autour de l'encoche", "Around the notch"),
                        subtitle: tr("Activités qui apparaissent sans ouvrir l'île.", "Activities that show up without opening the island."),
                        modules: registry.orderedModules.filter { $0.kind == .background })
            ChipSection(title: tr("En arrière-plan", "In the background"),
                        subtitle: tr("Services qui fonctionnent en dehors de l'île.", "Services that work outside the island."),
                        modules: registry.orderedModules.filter { $0.kind == .service })
        }
    }
}

// MARK: - Maquette de l'île

/// Maquette de l'île ouverte : onglets en haut, widgets de l'accueil en dessous.
private struct IslandLayoutPreview: View {
    private let registry = ModuleRegistry.shared

    var body: some View {
        let pages = registry.orderedModules.filter { $0.kind == .page }
        let widgets = registry.orderedModules.filter { $0.kind == .widget }

        VStack(alignment: .leading, spacing: 18) {
            // Barre d'onglets, de part et d'autre d'une encoche dessinée.
            HStack(spacing: 6) {
                TabChip(systemImage: "house.fill", tint: .gray, isEnabled: true, label: tr("Accueil", "Home"))
                ForEach(pages, id: \.id) { module in
                    DraggableModule(module: module) {
                        TabChip(systemImage: module.systemImage, tint: module.tint,
                                isEnabled: registry.isEnabled(module), label: module.name)
                    }
                }
                EndDropZone(kind: .page)
                Spacer(minLength: 20)
                Capsule().fill(Color.black).frame(width: 110, height: 22)
                Spacer(minLength: 20)
                Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.4))
            }

            Text(tr("Accueil", "Home"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            // Widgets de l'accueil, dans l'ordre d'affichage (de gauche à droite).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(widgets, id: \.id) { module in
                    DraggableModule(module: module) {
                        WidgetTile(module: module, isEnabled: registry.isEnabled(module))
                    }
                }
                EndDropZone(kind: .widget)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.07))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.25), value: registry.orderedModules.map(\.id))
    }
}

/// Onglet de la maquette (icône dans une capsule).
private struct TabChip: View {
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let label: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.3))
            .frame(width: 38, height: 28)
            .background(
                Capsule().fill(isEnabled ? tint.opacity(0.55) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(isEnabled ? 0 : 0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .help(label)
    }
}

/// Widget de la maquette : icône + nom.
private struct WidgetTile: View {
    let module: any IslandModule
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemImage: module.systemImage, tint: module.tint, size: 28)
                .saturation(isEnabled ? 1 : 0)
                .opacity(isEnabled ? 1 : 0.45)
            Text(module.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isEnabled ? .white : .white.opacity(0.35))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isEnabled ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isEnabled ? 0 : 0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

// MARK: - Glisser-déposer

/// Rend un module déplaçable (glisser), activable (clic) et réordonnable (dépôt sur un autre).
private struct DraggableModule<Content: View>: View {
    let module: any IslandModule
    @ViewBuilder let content: Content
    private let registry = ModuleRegistry.shared
    private let navigation = SettingsNavigation.shared

    var body: some View {
        content
            .opacity(navigation.draggedModule == module.id ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture { registry.setEnabled(!registry.isEnabled(module), for: module) }
            .onDrag {
                navigation.beginDrag(module.id)
                return NSItemProvider(object: module.id as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDropDelegate(targetID: module.id, kind: module.kind))
            .contextMenu {
                Button(registry.isEnabled(module) ? tr("Désactiver", "Turn off") : tr("Activer", "Turn on")) {
                    registry.setEnabled(!registry.isEnabled(module), for: module)
                }
                Button(tr("Réglages du module", "Module settings")) {
                    navigation.selection = .module(module.id)
                }
            }
            .help(module.summary)
    }
}

/// Réordonne en direct quand l'élément glissé passe au-dessus d'un autre du même type.
private struct ReorderDropDelegate: DropDelegate {
    let targetID: String
    let kind: ModuleKind

    @MainActor
    func dropEntered(info: DropInfo) {
        let navigation = SettingsNavigation.shared
        guard let dragged = navigation.draggedModule, dragged != targetID,
              ModuleRegistry.shared.module(id: dragged)?.kind == kind else { return }
        withAnimation(.smooth(duration: 0.25)) { ModuleRegistry.shared.move(dragged, before: targetID) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    @MainActor
    func performDrop(info: DropInfo) -> Bool {
        SettingsNavigation.shared.draggedModule = nil
        return true
    }
}

/// Zone de dépôt en fin de liste, pour placer un élément en dernier.
private struct EndDropZone: View {
    let kind: ModuleKind

    var body: some View {
        Color.clear
            .frame(width: kind == .page ? 24 : 40, height: kind == .page ? 28 : 52)
            .contentShape(Rectangle())
            .onDrop(of: [.text], delegate: EndDropDelegate(kind: kind))
    }
}

private struct EndDropDelegate: DropDelegate {
    let kind: ModuleKind

    @MainActor
    func dropEntered(info: DropInfo) {
        guard let dragged = SettingsNavigation.shared.draggedModule,
              ModuleRegistry.shared.module(id: dragged)?.kind == kind else { return }
        withAnimation(.smooth(duration: 0.25)) { ModuleRegistry.shared.moveToEnd(dragged) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    @MainActor
    func performDrop(info: DropInfo) -> Bool {
        SettingsNavigation.shared.draggedModule = nil
        return true
    }
}

// MARK: - Modules sans ordre

/// Modules dont l'ordre n'a pas d'importance : simples pastilles à activer ou désactiver.
private struct ChipSection: View {
    let title: String
    let subtitle: String
    let modules: [any IslandModule]
    private let registry = ModuleRegistry.shared
    private let navigation = SettingsNavigation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .padding(.leading, 6)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(modules, id: \.id) { module in
                    let enabled = registry.isEnabled(module)
                    Button {
                        registry.setEnabled(!enabled, for: module)
                    } label: {
                        HStack(spacing: 10) {
                            IconTile(systemImage: module.systemImage, tint: module.tint, size: 26)
                                .saturation(enabled ? 1 : 0)
                                .opacity(enabled ? 1 : 0.5)
                            Text(module.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(enabled ? .primary : .secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(enabled ? Color.accentColor : Color.primary.opacity(0.25))
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(tr("Réglages du module", "Module settings")) { navigation.selection = .module(module.id) }
                    }
                }
            }
        }
    }
}

private struct Legend: View {
    let enabled: Bool
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(enabled ? Color.primary.opacity(0.25) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(enabled ? 0 : 0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .frame(width: 16, height: 12)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}
