import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var url: URL
    /// Permet de retrouver un fichier référencé même s'il a été déplacé.
    var bookmark: Data?
    /// Vrai si le fichier est une copie appartenant à l'étagère (supprimée en même temps que l'élément).
    var isCopy: Bool
}

enum ShelfStorageMode: String, CaseIterable, Identifiable {
    case reference
    case copy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reference: tr("Référence", "Reference")
        case .copy: tr("Copie", "Copy")
        }
    }
}

@MainActor
@Observable
final class ShelfModule: FileDropReceiving {
    let id = "shelf"
    var name: String { tr("Étagère", "Shelf") }
    let systemImage = "tray.full.fill"
    var summary: String {
        tr("Dépose des fichiers sur l'encoche pour les garder sous la main, puis glisse-les ailleurs ou envoie-les par AirDrop.",
           "Drop files on the notch to keep them handy, then drag them elsewhere or send them with AirDrop.")
    }
    let tint = Color.indigo
    let kind = ModuleKind.page

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "shelf", registering: [
        "storageMode": ShelfStorageMode.reference.rawValue,
        "persistItems": true,
        "showAirDropZone": true,
        "removeAfterAirDrop": false,
    ])

    var storageMode: ShelfStorageMode { didSet { store.set(storageMode.rawValue, "storageMode") } }
    var persistItems: Bool { didSet { store.set(persistItems, "persistItems"); save() } }
    var showAirDropZone: Bool { didSet { store.set(showAirDropZone, "showAirDropZone") } }
    var removeAfterAirDrop: Bool { didSet { store.set(removeAfterAirDrop, "removeAfterAirDrop") } }

    private(set) var items: [ShelfItem] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    var isDropTargeted = false
    var isAirDropTargeted = false
    var hoveredItem: UUID?

    @ObservationIgnored private var didLoad = false

    private static let supportDirectory = URL.applicationSupportDirectory.appending(path: "Island", directoryHint: .isDirectory)
    private static let copiesDirectory = supportDirectory.appending(path: "Shelf", directoryHint: .isDirectory)
    private static let indexFile = supportDirectory.appending(path: "shelf.json")

    init() {
        storageMode = ShelfStorageMode(rawValue: store.string("storageMode")) ?? .reference
        persistItems = store.bool("persistItems")
        showAirDropZone = store.bool("showAirDropZone")
        removeAfterAirDrop = store.bool("removeAfterAirDrop")
    }

    func expandedView() -> AnyView { AnyView(ShelfView(module: self)) }
    func settingsView() -> AnyView? { AnyView(ShelfSettingsView(module: self)) }

    func start() {
        guard !didLoad else { return }
        didLoad = true
        load()
    }

    // MARK: Ajout / retrait

    func receive(_ providers: [NSItemProvider]) -> Bool {
        loadURLs(from: providers) { [weak self] urls in self?.add(urls) }
        return true
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.map(\.url.standardizedFileURL))
        for url in urls where !existing.contains(url.standardizedFileURL) {
            let id = UUID()
            var item = ShelfItem(id: id, url: url, bookmark: try? url.bookmarkData(), isCopy: false)
            if storageMode == .copy, let copy = copyIntoShelf(url, id: id) {
                item = ShelfItem(id: id, url: copy, bookmark: nil, isCopy: true)
            }
            items.append(item)
            makeThumbnail(for: item)
        }
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        if item.isCopy {
            try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
        }
        save()
    }

    func removeAll() {
        items.forEach(remove)
    }

    // MARK: Actions

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    /// Exécute une action rapide et ajoute le fichier produit à l'étagère.
    func perform(_ action: @escaping () async throws -> URL) {
        Task {
            do {
                let result = try await action()
                add([result])
            } catch {
                ActivityCenter.shared.show(LiveActivity(id: "shelf.error", priority: 3, duration: 3) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } trailing: {
                    Text(tr("Échec", "Failed")).foregroundStyle(.orange)
                })
            }
        }
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
        if removeAfterAirDrop {
            items.filter { urls.contains($0.url) }.forEach(remove)
        }
    }

    func airDrop(_ providers: [NSItemProvider]) -> Bool {
        loadURLs(from: providers) { [weak self] urls in self?.airDrop(urls) }
        return true
    }

    // MARK: Fichiers

    private func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let collector = URLCollector()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { completion(collector.urls) }
        }
    }

    private func copyIntoShelf(_ url: URL, id: UUID) -> URL? {
        let folder = Self.copiesDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        let destination = folder.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func makeThumbnail(for item: ShelfItem) {
        thumbnails[item.id] = NSWorkspace.shared.icon(forFile: item.url.path)
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 96, height: 96),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self?.items.contains(where: { $0.id == item.id }) == true {
                        self?.thumbnails[item.id] = image
                    }
                }
            }
        }
    }

    // MARK: Persistance

    private func save() {
        guard didLoad else { return }
        let fm = FileManager.default
        if persistItems {
            try? fm.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
            try? JSONEncoder().encode(items).write(to: Self.indexFile)
        } else {
            try? fm.removeItem(at: Self.indexFile)
        }
    }

    private func load() {
        guard persistItems,
              let data = try? Data(contentsOf: Self.indexFile),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else {
            // Sans persistance, les copies d'une session précédente ne servent plus.
            try? FileManager.default.removeItem(at: Self.copiesDirectory)
            return
        }

        items = saved.compactMap { item in
            var item = item
            if let bookmark = item.bookmark {
                var stale = false
                if let resolved = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) {
                    item.url = resolved
                    if stale { item.bookmark = try? resolved.bookmarkData() }
                }
            }
            return FileManager.default.fileExists(atPath: item.url.path) ? item : nil
        }
        items.forEach(makeThumbnail)
    }
}

/// Collecte thread-safe des URL chargées en arrière-plan.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] { lock.withLock { storage } }
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
}

// MARK: - Vue

private struct ShelfView: View {
    let module: ShelfModule

    var body: some View {
        HStack(spacing: 12) {
            if module.items.isEmpty {
                DropZone(systemImage: "tray.and.arrow.down.fill",
                         title: tr("Dépose des fichiers ici", "Drop files here"),
                         isTargeted: module.isDropTargeted)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(module.items) { item in
                            ShelfItemView(module: module, item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(module.isDropTargeted ? 0.5 : 0), lineWidth: 1.5)
                )
            }

            if module.showAirDropZone {
                DropZone(systemImage: "dot.radiowaves.left.and.right",
                         title: module.items.isEmpty ? "AirDrop" : tr("Tout envoyer", "Send all"),
                         isTargeted: module.isAirDropTargeted)
                    .frame(width: 96)
                    .onTapGesture { module.airDrop(module.items.map(\.url)) }
                    .onDrop(of: [.fileURL], isTargeted: Binding(
                        get: { module.isAirDropTargeted },
                        set: { module.isAirDropTargeted = $0 }
                    )) { providers in
                        module.airDrop(providers)
                    }
                    .help(tr("Dépose des fichiers ici pour les envoyer par AirDrop, ou clique pour envoyer tout le contenu de l'étagère",
                             "Drop files here to send them with AirDrop, or click to send everything on the shelf"))
            }
        }
    }
}

private struct DropZone: View {
    let systemImage: String
    let title: String
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.primary.opacity(isTargeted ? 1 : 0.55))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(isTargeted ? 0.12 : 0.04))
                .strokeBorder(Color.primary.opacity(isTargeted ? 0.5 : 0.18), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .animation(.smooth(duration: 0.2), value: isTargeted)
    }
}

private struct ShelfItemView: View {
    let module: ShelfModule
    let item: ShelfItem

    private var isHovered: Bool { module.hoveredItem == item.id }

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let thumbnail = module.thumbnails[item.id] {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    Image(systemName: "doc").font(.system(size: 28)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)

            Text(item.url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: 70)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(isHovered ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { module.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .gray)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .contentShape(Rectangle())
        .onHover { module.hoveredItem = $0 ? item.id : (isHovered ? nil : module.hoveredItem) }
        .onTapGesture(count: 2) { module.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button(tr("Ouvrir", "Open")) { module.open(item) }
            Button(tr("Afficher dans le Finder", "Show in Finder")) { module.revealInFinder(item) }
            Button(tr("Envoyer par AirDrop", "Send with AirDrop")) { module.airDrop([item.url]) }
            Button(tr("Copier", "Copy")) { FileActions.copyToPasteboard([item.url]) }
            Divider()
            Button(tr("Compresser en .zip", "Compress to .zip")) { module.perform { try await FileActions.zip([item.url]) } }
            if FileActions.isImage(item.url) {
                Menu(tr("Convertir en", "Convert to")) {
                    ForEach(FileActions.ImageFormat.allCases, id: \.self) { format in
                        Button(format.label) { module.perform { try await FileActions.convert(item.url, to: format) } }
                    }
                }
            }
            if module.items.count > 1 {
                Button(tr("Tout compresser en .zip", "Compress all to .zip")) { module.perform { try await FileActions.zip(module.items.map(\.url)) } }
            }
            Divider()
            Button(tr("Retirer de l'étagère", "Remove from shelf")) { module.remove(item) }
            Button(tr("Vider l'étagère", "Clear shelf")) { module.removeAll() }
        }
        .help(item.url.path)
    }
}

// MARK: - Réglages

private struct ShelfSettingsView: View {
    @Bindable var module: ShelfModule

    var body: some View {
        PickerRow(tr("Stockage des fichiers", "File storage"),
                  subtitle: module.storageMode == .reference
                      ? tr("L'étagère pointe vers le fichier d'origine.", "The shelf points to the original file.")
                      : tr("Une copie est gardée, même si l'original est supprimé.", "A copy is kept, even if the original is deleted."),
                  selection: $module.storageMode) {
            ForEach(ShelfStorageMode.allCases) { Text($0.label).tag($0) }
        }
        ToggleRow(tr("Conserver après redémarrage", "Keep after restart"),
                  subtitle: tr("Retrouver le contenu de l'étagère au prochain lancement.", "Restore the shelf contents on next launch."),
                  isOn: $module.persistItems)
        ToggleRow(tr("Zone AirDrop", "AirDrop zone"),
                  subtitle: tr("Affiche une zone de dépôt pour envoyer directement par AirDrop.", "Shows a drop zone to send straight with AirDrop."),
                  isOn: $module.showAirDropZone)
        ToggleRow(tr("Retirer après un envoi AirDrop", "Remove after AirDrop"), isOn: $module.removeAfterAirDrop)
        SettingsRow(tr("Contenu actuel", "Current contents"),
                    subtitle: tr("\(module.items.count) élément\(module.items.count > 1 ? "s" : "")",
                                 "\(module.items.count) item\(module.items.count == 1 ? "" : "s")")) {
            Button(tr("Vider", "Clear"), role: .destructive) { module.removeAll() }
                .disabled(module.items.isEmpty)
        }
    }
}
