import SwiftUI

/// Batteries d'un appareil Bluetooth audio, en pourcentage. `nil` = inconnu.
struct HeadphoneBatteries: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Batterie unique (casque, AirPods Max…).
    var main: Int?

    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && main == nil }

    /// Niveau résumé : la plus faible des deux oreillettes, sinon la batterie unique.
    var summary: Int? {
        let buds = [left, right].compactMap { $0 }
        return buds.min() ?? main
    }
}

/// Annonce la connexion d'AirPods ou d'un casque Bluetooth, avec le niveau de batterie.
///
/// Sans permission Bluetooth : la connexion est détectée quand la sortie audio bascule sur
/// un appareil Bluetooth, et les batteries sont lues dans le rapport `system_profiler`.
@MainActor
@Observable
final class AirPodsModule: IslandModule {
    let id = "airpods"
    var name: String { tr("AirPods & casques", "AirPods & Headphones") }
    let systemImage = "airpods"
    var summary: String {
        tr("Annonce la connexion d'AirPods ou d'un casque Bluetooth, avec la batterie.",
           "Announces AirPods or Bluetooth headphones when they connect, with their battery.")
    }
    let tint = Color.blue
    let kind = ModuleKind.background

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "airpods", registering: [
        "showBatteryDetails": true,
        "duration": 4.0,
    ])

    /// Détail gauche / droite / boîtier sous l'encoche (sinon un seul pourcentage).
    var showBatteryDetails: Bool { didSet { store.set(showBatteryDetails, "showBatteryDetails") } }
    var duration: Double { didSet { store.set(duration, "duration") } }

    private(set) var lastDevice: String?
    private(set) var lastBatteries: HeadphoneBatteries?

    @ObservationIgnored private var observer: AnyObject?
    @ObservationIgnored private var wasBluetooth = false

    init() {
        showBatteryDetails = store.bool("showBatteryDetails")
        duration = store.double("duration")
    }

    func expandedView() -> AnyView { AnyView(EmptyView()) }
    func settingsView() -> AnyView? { AnyView(AirPodsSettingsView(module: self)) }

    func start() {
        wasBluetooth = AudioDevices.isDefaultOutputBluetooth
        observer = AudioDevices.observeDefaultOutputDevice { [weak self] in self?.outputDidChange() }
    }

    func stop() {
        observer = nil
        ActivityCenter.shared.dismiss("airpods")
    }

    private func outputDidChange() {
        let isBluetooth = AudioDevices.isDefaultOutputBluetooth
        defer { wasBluetooth = isBluetooth }
        guard isBluetooth, !wasBluetooth, let name = AudioDevices.defaultOutputName else { return }
        announce(name)
    }

    /// Affiche l'activité tout de suite, puis la complète avec les batteries (lecture asynchrone).
    func announce(_ deviceName: String) {
        lastDevice = deviceName
        show(deviceName, batteries: nil)
        Task {
            let batteries = await Self.readBatteries(for: deviceName)
            lastBatteries = batteries
            if let batteries, !batteries.isEmpty { show(deviceName, batteries: batteries) }
        }
    }

    /// Exemple pour essayer sans appareil connecté.
    func announceSample() {
        show("AirPods Pro", batteries: HeadphoneBatteries(left: 85, right: 80, caseLevel: 60))
    }

    private func show(_ deviceName: String, batteries: HeadphoneBatteries?) {
        let symbol = Self.symbol(for: deviceName)
        let details = showBatteryDetails && batteries.map { $0.left != nil || $0.right != nil } == true
        let summary = batteries?.summary

        let leading = Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
        let trailing = Group {
            if let summary { BatteryRing(level: summary) } else { Text(tr("Connecté", "Connected")).font(.system(size: 11)) }
        }

        if details, let batteries {
            ActivityCenter.shared.show(LiveActivity(id: "airpods", priority: 3, duration: duration,
                                                    sideWidth: 74, bottomHeight: 30) {
                leading
            } trailing: {
                trailing
            } bottom: {
                HStack(spacing: 18) {
                    BatteryLabel(systemImage: "l.circle.fill", level: batteries.left)
                    BatteryLabel(systemImage: "r.circle.fill", level: batteries.right)
                    BatteryLabel(systemImage: "airpods.chargingcase.fill", level: batteries.caseLevel)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.bottom, 6)
            })
        } else {
            ActivityCenter.shared.show(LiveActivity(id: "airpods", priority: 3, duration: duration) {
                leading
            } trailing: {
                trailing
            })
        }
    }

    // MARK: Lecture des batteries

    /// Cherche l'appareil connecté dans `system_profiler SPBluetoothDataType -json`.
    private static func readBatteries(for deviceName: String) async -> HeadphoneBatteries? {
        // Lecture du tube pendant l'exécution (en arrière-plan) : attendre la fin du processus
        // avant de lire bloquerait si la sortie dépasse la taille du tube (~64 Ko).
        let output: Data? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(filePath: "/usr/sbin/system_profiler")
                process.arguments = ["SPBluetoothDataType", "-json"]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
        guard let output,
              let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }

        for section in sections {
            for device in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in device {
                    guard let properties = value as? [String: Any],
                          names(name, matchAudioDevice: deviceName) else { continue }
                    return HeadphoneBatteries(
                        left: percent(properties["device_batteryLevelLeft"]),
                        right: percent(properties["device_batteryLevelRight"]),
                        caseLevel: percent(properties["device_batteryLevelCase"]),
                        main: percent(properties["device_batteryLevelMain"]))
                }
            }
        }
        return nil
    }

    /// Les noms Bluetooth et CoreAudio sont en général identiques ; on tolère de petites différences.
    private static func names(_ bluetoothName: String, matchAudioDevice audioName: String) -> Bool {
        let a = bluetoothName.lowercased(), b = audioName.lowercased()
        return a == b || a.contains(b) || b.contains(a)
    }

    private static func percent(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    static func symbol(for deviceName: String) -> String {
        let name = deviceName.lowercased()
        if name.contains("airpods max") { return "airpods.max" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        return "headphones"
    }
}

// MARK: - Vues

/// Anneau de batterie compact, vert, orange sous 20 %.
private struct BatteryRing: View {
    let level: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("\(level) %").monospacedDigit()
            ZStack {
                Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(level <= 20 ? Color.orange : Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
        }
    }
}

private struct BatteryLabel: View {
    let systemImage: String
    let level: Int?

    var body: some View {
        if let level {
            Label("\(level) %", systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(level <= 20 ? Color.orange : Color.primary)
                .monospacedDigit()
        }
    }
}

// MARK: - Réglages

private struct AirPodsSettingsView: View {
    @Bindable var module: AirPodsModule

    var body: some View {
        ToggleRow(tr("Détail des batteries", "Battery details"),
                  subtitle: tr("Gauche, droite et boîtier sous l'encoche, quand c'est disponible.",
                               "Left, right and case below the notch, when available."),
                  isOn: $module.showBatteryDetails)
        SliderRow(tr("Durée d'affichage", "Display duration"), value: $module.duration, range: 2...8, step: 0.5) {
            String(format: "%.1f s", $0)
        }
        SettingsRow(tr("Essayer", "Try it"),
                    subtitle: module.lastDevice.map { tr("Dernier appareil : \($0)", "Last device: \($0)") }
                        ?? tr("Connecte des AirPods pour voir l'annonce.", "Connect AirPods to see the announcement.")) {
            Button(tr("Afficher", "Show")) {
                if let device = module.lastDevice { module.announce(device) } else { module.announceSample() }
            }
        }
    }
}
