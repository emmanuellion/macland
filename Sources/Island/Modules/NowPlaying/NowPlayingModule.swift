import AppKit
import CoreImage
import SwiftUI

enum SkipMode: String, CaseIterable, Identifiable {
    case track
    case seconds

    var id: String { rawValue }

    var label: String {
        switch self {
        case .track: tr("Morceau", "Track")
        case .seconds: "15 s"
        }
    }
}

@MainActor
@Observable
final class NowPlayingModule: IslandModule {
    let id = "nowPlaying"
    var name: String { tr("Lecture en cours", "Now Playing") }
    let systemImage = "music.note"
    var summary: String {
        tr("Pochette, titre et contrôles du morceau en cours (Spotify, Musique, navigateurs…).",
           "Artwork, title and controls for the current track (Spotify, Music, browsers…).")
    }
    let tint = Color.pink
    /// Prend la place restante sur l'accueil seulement quand quelque chose joue ;
    /// sinon les widgets sont centrés.
    var layoutPriority: Double { info == nil ? 0 : 1 }

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "nowPlaying", registering: [
        "liveActivity": true,
        "artworkTint": true,
        "showProgress": true,
        "showAppIcon": true,
        "hideWhenIdle": true,
        "skipMode": SkipMode.track.rawValue,
        "showOutputPicker": true,
    ])

    /// Pochette + égaliseur autour de l'encoche fermée pendant la lecture.
    var liveActivity: Bool { didSet { store.set(liveActivity, "liveActivity"); updateActivity() } }
    /// Couleur dominante de la pochette pour l'égaliseur et la barre de progression.
    var artworkTint: Bool { didSet { store.set(artworkTint, "artworkTint"); updateActivity() } }
    var showProgress: Bool { didSet { store.set(showProgress, "showProgress") } }
    var showAppIcon: Bool { didSet { store.set(showAppIcon, "showAppIcon") } }
    var hideWhenIdle: Bool { didSet { store.set(hideWhenIdle, "hideWhenIdle") } }
    var skipMode: SkipMode { didSet { store.set(skipMode.rawValue, "skipMode") } }
    /// Bouton de choix de la sortie audio (haut-parleurs, AirPods…).
    var showOutputPicker: Bool { didSet { store.set(showOutputPicker, "showOutputPicker") } }

    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    /// Teinte (0…1) et saturation de la couleur dominante de la pochette.
    private(set) var artworkHue: (hue: Double, saturation: Double)?
    private(set) var error: String?
    /// Position (0…1) pendant que l'utilisateur fait glisser la barre de progression.
    var scrubFraction: Double?
    var isHoveringProgress = false
    #if DEBUG
    @ObservationIgnored var debugProgressFrame: CGRect = .zero
    #endif

    @ObservationIgnored private let adapter = MediaRemoteAdapter()
    /// Après un saut, le lecteur peut encore envoyer l'ancienne position : on l'ignore un court instant.
    @ObservationIgnored private var seekGuard: (position: Double, until: Date)?

    init() {
        liveActivity = store.bool("liveActivity")
        artworkTint = store.bool("artworkTint")
        showProgress = store.bool("showProgress")
        showAppIcon = store.bool("showAppIcon")
        hideWhenIdle = store.bool("hideWhenIdle")
        skipMode = SkipMode(rawValue: store.string("skipMode")) ?? .track
        showOutputPicker = store.bool("showOutputPicker")

        adapter.onUpdate = { [weak self] info, artwork in self?.update(info: info, artwork: artwork) }
        adapter.onFailure = { [weak self] message in self?.error = message }
    }

    var isVisibleInHome: Bool { !(hideWhenIdle && info == nil) }

    /// Couleur d'accent de l'île ouverte : pochette si activé, sinon couleur du texte.
    var accent: Color { accent(onDarkBackground: IslandSettings.shared.islandColor.isDark) }

    /// Claire sur fond noir, foncée sur fond pastel.
    func accent(onDarkBackground dark: Bool) -> Color {
        guard artworkTint, let artworkHue else { return dark ? .white : .black.opacity(0.8) }
        return Color(hue: artworkHue.hue, saturation: min(1, artworkHue.saturation * 1.4),
                     brightness: dark ? 0.9 : 0.45)
    }

    func expandedView() -> AnyView { AnyView(NowPlayingView(module: self)) }
    func settingsView() -> AnyView? { AnyView(NowPlayingSettingsView(module: self)) }

    func start() {
        error = MediaRemoteAdapter.isAvailable ? nil
            : tr("Adaptateur absent : lance l'app depuis Island.app (scripts/build-app.sh).",
                 "Adapter missing: launch the app from Island.app (scripts/build-app.sh).")
        #if DEBUG
        // Simule « rien en lecture » pour les captures.
        if CommandLine.arguments.contains("--no-media") { return }
        // Morceau fictif pour les captures publiques (pas d'écoute personnelle à l'écran).
        if CommandLine.arguments.contains("--demo-media") {
            update(info: NowPlayingInfo(title: "Neon Harbor", artist: "The Islanders", album: "Afterglow",
                                        bundleIdentifier: "com.apple.Music", isPlaying: true, duration: 214,
                                        elapsed: 83, timestamp: .now, playbackRate: 1),
                   artwork: Self.demoArtwork())
            return
        }
        #endif
        adapter.start()
    }

    func stop() {
        adapter.stop()
        info = nil
        artwork = nil
        ActivityCenter.shared.dismiss("nowPlaying")
    }

    // MARK: Contrôles

    func togglePlayPause() {
        // On fige la position avant de changer d'état, sinon la barre saute en attendant la mise à jour.
        if let current = info {
            info?.elapsed = current.elapsed(at: .now)
            info?.timestamp = .now
        }
        info?.isPlaying.toggle()
        adapter.send(.togglePlayPause)
        updateActivity()
    }

    #if DEBUG
    func debugSend(_ command: MediaRemoteAdapter.Command) { adapter.send(command) }
    #endif

    func next() { adapter.send(skipMode == .track ? .nextTrack : .skip15) }
    func previous() { adapter.send(skipMode == .track ? .previousTrack : .goBack15) }

    func seek(toFraction fraction: Double) {
        guard let duration = info?.duration, duration > 0 else { return }
        let position = duration * min(max(fraction, 0), 1)
        info?.elapsed = position
        info?.timestamp = .now
        seekGuard = (position, Date.now.addingTimeInterval(2.5))
        debugLog("seek → \(String(format: "%.2f", position)) s")
        adapter.seek(to: position)
    }

    func openSourceApp() {
        guard let bundleID = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    var sourceAppIcon: NSImage? {
        guard let bundleID = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    #if DEBUG
    private static func demoArtwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.45, blue: 0.35, alpha: 1),
                                NSColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1)])?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 95, dy: 95)).fill()
            return true
        }
    }
    #endif

    // MARK: Mises à jour

    private func update(info: NowPlayingInfo?, artwork: NSImage?) {
        if let info { debugLog("update playing=\(info.isPlaying) elapsedNow=\(String(format: "%.2f", info.elapsed(at: .now))) duration=\(info.duration ?? -1)") }
        error = nil
        var info = info
        if let guarded = seekGuard, let current = self.info, var incoming = info {
            let expected = current.elapsed(at: .now)
            if Date.now > guarded.until || abs(incoming.elapsed(at: .now) - expected) < 1.5 {
                seekGuard = nil
            } else if incoming.title == current.title {
                // Position périmée : on garde la nôtre.
                incoming.elapsed = expected
                incoming.timestamp = .now
                info = incoming
                debugLog("update ignorée (position antérieure au saut)")
            }
        }
        self.info = info
        if artwork !== self.artwork {
            self.artwork = artwork
            artworkHue = artwork?.dominantHue
        }
        updateActivity()
    }

    private func updateActivity() {
        guard liveActivity, let info, info.isPlaying else {
            ActivityCenter.shared.dismiss("nowPlaying")
            return
        }
        let artwork = artwork
        // L'île fermée est toujours noire.
        let accent = accent(onDarkBackground: true)
        ActivityCenter.shared.show(LiveActivity(id: "nowPlaying", priority: -1, duration: nil) {
            ArtworkView(image: artwork, size: 22, cornerRadius: 5)
        } trailing: {
            EqualizerBars(color: accent, isPlaying: info.isPlaying)
                .frame(width: 20, height: 14)
        })
    }
}

// MARK: - Vues

private struct NowPlayingView: View {
    let module: NowPlayingModule

    var body: some View {
        if let info = module.info {
            HStack(spacing: 14) {
                ArtworkView(image: module.artwork, size: 72, cornerRadius: 14)
                    .overlay(alignment: .bottomTrailing) {
                        if module.showAppIcon, let icon = module.sourceAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .offset(x: 6, y: 6)
                        }
                    }
                    .onTapGesture { module.openSourceApp() }
                    .help(tr("Ouvrir l'app", "Open app"))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            Text(info.artist.isEmpty ? info.album : info.artist)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.55))
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                        if module.showOutputPicker { OutputPicker() }
                    }

                    if module.showProgress, let duration = info.duration, duration > 0 {
                        ProgressBar(module: module, info: info, duration: duration)
                    }

                    HStack(spacing: 22) {
                        ControlButton(systemImage: module.skipMode == .track ? "backward.fill" : "gobackward.15", size: 14) {
                            module.previous()
                        }
                        ControlButton(systemImage: info.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                            module.togglePlayPause()
                        }
                        ControlButton(systemImage: module.skipMode == .track ? "forward.fill" : "goforward.15", size: 14) {
                            module.next()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.primary.opacity(0.4))
                Text(module.error ?? tr("Rien en lecture", "Nothing playing"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Barre de progression utilisable comme un curseur : on la fait glisser, la position
/// visée s'affiche, et la lecture saute à cet endroit au relâchement.
private struct ProgressBar: View {
    let module: NowPlayingModule
    let info: NowPlayingInfo
    let duration: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !info.isPlaying)) { context in
            let isScrubbing = module.scrubFraction != nil
            let elapsed = module.scrubFraction.map { $0 * duration } ?? info.elapsed(at: context.date)
            let fraction = min(max(elapsed / duration, 0), 1)
            let isActive = isScrubbing || module.isHoveringProgress
            let barHeight: CGFloat = isActive ? 7 : 4

            VStack(spacing: 3) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: barHeight)
                        Capsule()
                            .fill(module.accent)
                            .frame(width: max(barHeight, width * fraction), height: barHeight)
                        if isActive {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 13, height: 13)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                                .offset(x: width * fraction - 6.5)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { module.isHoveringProgress = $0 }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                module.scrubFraction = min(max(value.location.x / width, 0), 1)
                                debugLog("scrub onChanged x=\(value.location.x) width=\(width) → \(module.scrubFraction!)")
                            }
                            .onEnded { value in
                                debugLog("scrub onEnded x=\(value.location.x) width=\(width)")
                                module.seek(toFraction: min(max(value.location.x / width, 0), 1))
                                module.scrubFraction = nil
                            }
                    )
                    .animation(.smooth(duration: 0.15), value: isActive)
                }
                .frame(height: 14)
                #if DEBUG
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { module.debugProgressFrame = $0 }
                #endif

                HStack {
                    Text(Self.format(elapsed))
                        .foregroundStyle(isScrubbing ? Color.primary : Color.primary.opacity(0.5))
                    Spacer()
                    Text("-" + Self.format(max(0, duration - elapsed)))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
            }
            .onDisappear { module.isHoveringProgress = false }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Menu de choix de la sortie audio par défaut.
private struct OutputPicker: View {
    var body: some View {
        Menu {
            let current = AudioDevices.defaultOutput
            ForEach(AudioDevices.outputDevices) { device in
                Button {
                    AudioDevices.setDefaultOutput(device.id)
                } label: {
                    if device.id == current {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Sortie audio", "Audio output"))
    }
}

private struct ControlButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.primary.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Égaliseur décoratif (le vrai spectre audio demanderait une capture du son système).
struct EqualizerBars: View {
    let color: Color
    let isPlaying: Bool

    private static let speeds: [Double] = [5.1, 7.3, 4.2, 6.4]
    private static let phases: [Double] = [0, 1.3, 2.6, 0.7]

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let level = isPlaying ? (sin(time * Self.speeds[index] + Self.phases[index]) + 1) / 2 : 0
                    Capsule()
                        .fill(color)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: 0.25 + 0.75 * level)
                }
            }
        }
    }
}

private extension NSImage {
    /// Teinte et saturation de la couleur moyenne de l'image.
    var dominantHue: (hue: Double, saturation: Double)? {
        guard let tiff = tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: input.extent),
              ]),
              let output = filter.outputImage
        else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let average = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (Double(hue), Double(saturation))
    }
}

// MARK: - Réglages

private struct NowPlayingSettingsView: View {
    @Bindable var module: NowPlayingModule

    var body: some View {
        if let error = module.error {
            SettingsRow(tr("État", "Status"), subtitle: error) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        ToggleRow(tr("Activité pendant la lecture", "Activity while playing"),
                  subtitle: tr("Pochette et égaliseur autour de l'encoche fermée.", "Artwork and equalizer around the closed notch."),
                  isOn: $module.liveActivity)
        ToggleRow(tr("Couleur de la pochette", "Artwork color"),
                  subtitle: tr("Teinte l'égaliseur et la barre de progression.", "Tints the equalizer and progress bar."),
                  isOn: $module.artworkTint)
        ToggleRow(tr("Barre de progression", "Progress bar"),
                  subtitle: tr("Fais-la glisser pour te déplacer dans le morceau.", "Drag it to scrub through the track."),
                  isOn: $module.showProgress)
        ToggleRow(tr("Icône de l'app source", "Source app icon"), isOn: $module.showAppIcon)
        ToggleRow(tr("Choix de la sortie audio", "Audio output picker"),
                  subtitle: tr("Bouton pour passer des haut-parleurs aux AirPods, etc.", "Button to switch from speakers to AirPods, etc."),
                  isOn: $module.showOutputPicker)
        PickerRow(tr("Boutons précédent / suivant", "Previous / next buttons"),
                  subtitle: tr("15 s est pratique pour les podcasts et vidéos.", "15 s is handy for podcasts and videos."),
                  selection: $module.skipMode) {
            ForEach(SkipMode.allCases) { Text($0.label).tag($0) }
        }
        ToggleRow(tr("Masquer quand rien ne joue", "Hide when nothing is playing"),
                  subtitle: tr("Libère la place pour les autres widgets.", "Frees up room for the other widgets."),
                  isOn: $module.hideWhenIdle)
    }
}
