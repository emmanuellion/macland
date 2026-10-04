import CoreGraphics
import Foundation

/// Luminosité de l'écran intégré via le framework privé DisplayServices
/// (pas d'API publique pour ça sur les Mac Apple Silicon).
enum DisplayBrightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFunction = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFunction.self) }
    private static let setFunction = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFunction.self) }

    static var isAvailable: Bool { getFunction != nil && setFunction != nil && builtInDisplay != nil }

    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Luminosité (0…1) de l'écran intégré.
    static var value: Float? {
        guard let getFunction, let display = builtInDisplay else { return nil }
        var brightness: Float = 0
        return getFunction(display, &brightness) == 0 ? brightness : nil
    }

    static func set(_ brightness: Float) {
        guard let setFunction, let display = builtInDisplay else { return }
        _ = setFunction(display, min(max(brightness, 0), 1))
    }
}
