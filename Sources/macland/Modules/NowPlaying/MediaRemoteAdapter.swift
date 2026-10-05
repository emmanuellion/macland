import AppKit

/// Ce qui est en cours de lecture.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var bundleIdentifier: String
    var isPlaying: Bool
    var duration: Double?
    /// Position de lecture au moment de `timestamp`.
    var elapsed: Double
    var timestamp: Date
    var playbackRate: Double

    /// Position actuelle, extrapolée depuis la dernière mise à jour.
    func elapsed(at date: Date) -> Double {
        guard isPlaying else { return elapsed }
        let position = elapsed + date.timeIntervalSince(timestamp) * playbackRate
        return min(max(0, position), duration ?? .infinity)
    }
}

/// Pilote `mediaremote-adapter.pl`, exécuté par /usr/bin/perl qui a le droit d'utiliser MediaRemote.
/// Voir Vendor/mediaremote-adapter/README.md.
@MainActor
final class MediaRemoteAdapter {
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
        case goBack15 = 12
        case skip15 = 13
    }

    /// Appelé à chaque changement. `nil` = rien en lecture.
    var onUpdate: ((NowPlayingInfo?, NSImage?) -> Void)?
    /// Appelé si l'adaptateur échoue à répétition (ex. : une mise à jour d'Apple l'a cassé).
    var onFailure: ((String) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var payload: [String: Any] = [:]
    private var artworkData: Data?
    private var artwork: NSImage?
    private var isRunning = false
    /// Dernière info envoyée, pour extrapoler la position quand le lecteur ne la fournit pas.
    private var lastInfo: NowPlayingInfo?
    /// Position imposée tant que le lecteur n'a pas renvoyé de position fraîche (voir `handleLine`).
    private var timingOverride: (elapsed: Double, timestamp: Date)?

    private static let timingKeys: Set<String> = ["elapsedTimeMicros", "timestampEpochMicros", "playbackRate"]
    private var failures = 0

    private static let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
    private static let frameworkURL = Bundle.main.privateFrameworksURL?.appending(path: "MediaRemoteAdapter.framework")

    static var isAvailable: Bool {
        guard let scriptURL, let frameworkURL else { return false }
        return FileManager.default.fileExists(atPath: scriptURL.path) && FileManager.default.fileExists(atPath: frameworkURL.path)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        failures = 0
        launchStream()
    }

    func stop() {
        isRunning = false
        process?.terminate()
        process = nil
        payload = [:]
        artworkData = nil
        artwork = nil
        lastInfo = nil
        timingOverride = nil
    }

    func send(_ command: Command) {
        runOnce(["send", String(command.rawValue)])
    }

    func seek(to seconds: Double) {
        runOnce(["seek", String(Int(max(0, seconds) * 1_000_000))])
    }

    // MARK: Process

    private func arguments(_ command: [String]) -> [String]? {
        guard let scriptURL = Self.scriptURL, let frameworkURL = Self.frameworkURL else { return nil }
        return [scriptURL.path, frameworkURL.path] + command
    }

    private func runOnce(_ command: [String]) {
        guard let arguments = arguments(command) else { return }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/perl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func launchStream() {
        guard isRunning else { return }
        guard let arguments = arguments(["stream", "--micros", "--debounce=50"]) else {
            onFailure?(tr("Adaptateur introuvable dans l'app. Recompile avec scripts/build-app.sh.",
                          "Adapter not found in the app. Rebuild with scripts/build-app.sh."))
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/perl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Les rappels d'un ancien processus (module arrêté puis relancé) sont ignorés : sinon ils
        // remettaient des infos après l'arrêt, ou effaçaient la référence au nouveau flux.
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isRunning, let process, self.process === process else { return }
                    self.receive(data)
                }
            }
        }

        process.terminationHandler = { [weak self] exited in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.process === exited else { return }
                    self.streamDidExit()
                }
            }
        }

        buffer.removeAll()
        payload = [:]
        do {
            try process.run()
            self.process = process
        } catch {
            streamDidExit()
        }
    }

    private func streamDidExit() {
        process = nil
        guard isRunning else { return }
        failures += 1
        if failures >= 5 {
            onFailure?(tr("La lecture en cours ne répond plus (une mise à jour de macOS a peut-être cassé l'adaptateur).",
                          "Now Playing stopped responding (a macOS update may have broken the adapter)."))
            isRunning = false
            return
        }
        // Relance avec un délai croissant.
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(failures) * 2) { [weak self] in
            MainActor.assumeIsolated { self?.launchStream() }
        }
    }

    // MARK: Parsing

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handleLine(Data(line))
        }
    }

    private func handleLine(_ line: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let update = message["payload"] as? [String: Any]
        else { return }

        failures = 0
        let isDiff = message["diff"] as? Bool == true

        // Seule une position fraîche (`elapsedTimeMicros`) fait foi. Observé avec Spotify :
        // - au passage lecture ↔ pause, `playing` arrive seul avec la position de la dernière
        //   lecture : la barre sautait en arrière. On fige la position actuelle ;
        // - au démarrage, un nouvel horodatage arrive sans nouvelle position : la barre reculait.
        //   On garde l'ancrage précédent.
        if !isDiff || update["elapsedTimeMicros"] != nil {
            timingOverride = nil
        } else if let playing = update["playing"] as? Bool, let last = lastInfo, playing != last.isPlaying {
            timingOverride = (last.elapsed(at: .now), .now)
        } else if timingOverride == nil, update.keys.contains(where: Self.timingKeys.contains), let last = lastInfo {
            timingOverride = (last.elapsed, last.timestamp)
        }

        if isDiff {
            for (key, value) in update {
                if value is NSNull { payload.removeValue(forKey: key) } else { payload[key] = value }
            }
        } else {
            payload = update
        }

        updateArtwork()
        var info = makeInfo()
        if let override = timingOverride {
            info?.elapsed = override.elapsed
            info?.timestamp = override.timestamp
        }
        lastInfo = info
        onUpdate?(info, artwork)
    }

    private func updateArtwork() {
        guard let base64 = payload["artworkData"] as? String else {
            artworkData = nil
            artwork = nil
            return
        }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), data != artworkData else { return }
        artworkData = data
        artwork = NSImage(data: data)
    }

    private func makeInfo() -> NowPlayingInfo? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        let micros = { (key: String) in (self.payload[key] as? NSNumber)?.doubleValue }
        return NowPlayingInfo(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            bundleIdentifier: payload["bundleIdentifier"] as? String ?? "",
            isPlaying: payload["playing"] as? Bool ?? false,
            duration: micros("durationMicros").map { $0 / 1_000_000 },
            elapsed: (micros("elapsedTimeMicros") ?? 0) / 1_000_000,
            timestamp: micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? .now,
            playbackRate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        )
    }
}
