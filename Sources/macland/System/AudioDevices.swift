import AppKit
import AudioToolbox
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
}

/// Accès CoreAudio : volume et sourdine de la sortie, liste et choix des sorties, micros actifs.
enum AudioDevices {
    // MARK: Sortie par défaut

    static var defaultOutput: AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        guard get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &device),
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func setDefaultOutput(_ device: AudioObjectID) {
        var device = device
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &device)
    }

    /// Volume (0…1) de la sortie par défaut. `nil` si l'appareil n'a pas de volume réglable (ex. HDMI).
    static var volume: Float? {
        guard let device = defaultOutput else { return nil }
        var value: Float32 = 0
        return get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, &value, scope: kAudioDevicePropertyScopeOutput)
            ? value : nil
    }

    static var canSetVolume: Bool {
        guard let device = defaultOutput else { return false }
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func setVolume(_ value: Float) {
        guard let device = defaultOutput else { return }
        var value = Float32(min(max(value, 0), 1))
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if value > 0, isMuted { setMuted(false) }
    }

    static var isMuted: Bool {
        guard let device = defaultOutput else { return false }
        var value: UInt32 = 0
        return get(device, kAudioDevicePropertyMute, &value, scope: kAudioDevicePropertyScopeOutput) && value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutput else { return }
        var value: UInt32 = muted ? 1 : 0
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: Listes

    static var outputDevices: [AudioDevice] { devices(withStreamsIn: kAudioDevicePropertyScopeOutput) }

    /// Services système qui écoutent en permanence (Siri…) : l'indicateur d'Apple les ignore aussi.
    private static let ignoredInputProcesses: Set<String> = [
        "com.apple.CoreSpeech", "com.apple.corespeechd", "com.apple.corespeechd_system", "com.apple.assistantd",
        "com.apple.accessibility.heard", "com.apple.universalaccessd", "com.apple.audiomxd",
        "com.apple.audio.Core-Audio-Driver-Service.helper", "systemsoundserverd",
    ]

    /// Noms des apps qui enregistrent actuellement avec un micro.
    /// Par processus (macOS 14+) : un casque qui joue de la musique ne compte pas comme micro actif.
    static var appsUsingMicrophone: [String] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr else { return [] }

        var names: [String] = []
        for process in processes {
            var running: UInt32 = 0
            guard get(process, kAudioProcessPropertyIsRunningInput, &running), running != 0 else { continue }
            let bundleID = string(of: process, kAudioProcessPropertyBundleID) ?? ""
            guard !ignoredInputProcesses.contains(bundleID) else { continue }
            var pid: pid_t = 0
            _ = get(process, kAudioProcessPropertyPID, &pid)
            let name = appName(bundleID: bundleID, pid: pid)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Nom lisible d'un processus, en remontant des processus auxiliaires vers leur app
    /// (ex. : com.google.Chrome.helper → Google Chrome).
    private static func appName(bundleID: String, pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, let name = app.localizedName {
            return name
        }
        if bundleID.hasPrefix("com.apple.WebKit") { return "Safari" }
        var candidate = bundleID
        while let dot = candidate.lastIndex(of: ".") {
            candidate = String(candidate[..<dot])
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? (bundleID.isEmpty ? "Une app" : bundleID)
    }

    private static func string(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func devices(withStreamsIn scope: AudioObjectPropertyScope) -> [AudioDevice] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streamsAddress = Self.address(kAudioDevicePropertyStreams, scope: scope)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }
            return AudioDevice(id: id, name: name(of: id))
        }
    }

    private static func name(of device: AudioObjectID) -> String {
        string(of: device, kAudioObjectPropertyName) ?? "?"
    }

    /// Nom de la sortie par défaut (ex. : « AirPods Pro de … »).
    static var defaultOutputName: String? { defaultOutput.map(name(of:)) }

    /// Vrai si la sortie par défaut est un appareil Bluetooth (AirPods, casque…).
    static var isDefaultOutputBluetooth: Bool {
        guard let device = defaultOutput else { return false }
        var transport: UInt32 = 0
        guard get(device, kAudioDevicePropertyTransportType, &transport) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Appelle `handler` quand la sortie audio par défaut change (branchement d'AirPods, etc.).
    static func observeDefaultOutputDevice(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        DefaultDeviceObserver(handler: handler)
    }

    private final class DefaultDeviceObserver {
        private lazy var block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handler() }
        }
        private let handler: @MainActor () -> Void

        init(handler: @escaping @MainActor () -> Void) {
            self.handler = handler
            var address = AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }

        deinit {
            var address = AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }

    // MARK: Observation

    /// Appelle `handler` quand le volume, la sourdine ou la sortie par défaut changent.
    /// Renvoie un objet à conserver ; l'observation s'arrête quand il est libéré.
    static func observeOutput(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        OutputObserver(handler: handler)
    }

    private final class OutputObserver {
        private let handler: @MainActor () -> Void
        private var observedDevice: AudioObjectID?
        private let queue = DispatchQueue.main
        private lazy var deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handler() }
        }
        private lazy var defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.attachToDefaultDevice()
                self?.handler()
            }
        }

        init(handler: @escaping @MainActor () -> Void) {
            self.handler = handler
            var address = AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, defaultBlock)
            attachToDefaultDevice()
        }

        deinit {
            detach()
            var address = AudioDevices.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, defaultBlock)
        }

        private func attachToDefaultDevice() {
            detach()
            guard let device = AudioDevices.defaultOutput else { return }
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = AudioDevices.address(selector, scope: kAudioDevicePropertyScopeOutput)
                AudioObjectAddPropertyListenerBlock(device, &address, queue, deviceBlock)
            }
            observedDevice = device
        }

        private func detach() {
            guard let device = observedDevice else { return }
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = AudioDevices.address(selector, scope: kAudioDevicePropertyScopeOutput)
                AudioObjectRemovePropertyListenerBlock(device, &address, queue, deviceBlock)
            }
            observedDevice = nil
        }
    }

    // MARK: Utilitaires

    fileprivate static func address(_ selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Lecture d'une propriété de type valeur simple (nombres, identifiants).
    private static func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = Self.address(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
