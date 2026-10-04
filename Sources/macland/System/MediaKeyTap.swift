import AppKit

enum MediaKey {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    /// Codes `NX_KEYTYPE_*` de IOKit/hidsystem/ev_keymap.h.
    init?(keyType: Int) {
        switch keyType {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        default: return nil
        }
    }
}

/// Intercepte les touches volume / luminosité (événements « system defined »).
/// Nécessite la permission Accessibilité. Le handler renvoie `true` pour retirer l'événement,
/// ce qui empêche macOS d'afficher son propre HUD.
@MainActor
final class MediaKeyTap {
    typealias Handler = @MainActor (MediaKey, _ isRepeat: Bool, NSEvent.ModifierFlags) -> Bool

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: Handler
    /// Touches dont l'appui a été pris en charge : on retire aussi leur relâchement.
    private var consumedKeys: Set<Int> = []

    private static let systemDefinedType = CGEventType(rawValue: 14)! // NX_SYSDEFINED

    init?(handler: @escaping Handler) {
        self.handler = handler
        let mask = CGEventMask(1) << Self.systemDefinedType.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MediaKeyTap>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { tap.process(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return nil }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS désactive le tap s'il répond trop lentement : on le réactive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == Self.systemDefinedType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 // NX_SUBTYPE_AUX_CONTROL_BUTTONS
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        let keyType = (data & 0xFFFF_0000) >> 16
        let isDown = ((data & 0xFF00) >> 8) == 0xA
        let isRepeat = (data & 0x1) == 1
        guard let key = MediaKey(keyType: keyType) else { return Unmanaged.passUnretained(event) }

        if isDown {
            if handler(key, isRepeat, nsEvent.modifierFlags) {
                consumedKeys.insert(keyType)
                return nil
            }
            consumedKeys.remove(keyType)
            return Unmanaged.passUnretained(event)
        }
        return consumedKeys.remove(keyType) != nil ? nil : Unmanaged.passUnretained(event)
    }
}
