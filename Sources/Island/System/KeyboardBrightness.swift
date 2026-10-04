import Foundation

/// Rétroéclairage du clavier via la classe privée `KeyboardBrightnessClient` (CoreBrightness).
@MainActor
enum KeyboardBrightness {
    private typealias GetFunction = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFunction = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    private static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = type.init()
        return client.responds(to: getSelector) && client.responds(to: setSelector) ? client : nil
    }()

    private static let keyboardID: UInt64? = {
        guard let client,
              let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return ids.first?.uint64Value
    }()

    static var isAvailable: Bool { client != nil && keyboardID != nil }

    /// Luminosité (0…1) du clavier intégré.
    static var value: Float? {
        guard let client, let keyboardID else { return nil }
        let get = unsafeBitCast(client.method(for: getSelector), to: GetFunction.self)
        return get(client, getSelector, keyboardID)
    }

    static func set(_ brightness: Float) {
        guard let client, let keyboardID else { return }
        let set = unsafeBitCast(client.method(for: setSelector), to: SetFunction.self)
        _ = set(client, setSelector, min(max(brightness, 0), 1), keyboardID)
    }
}
