import Foundation

/// Journal de développement (horodaté). Ne fait rien dans l'app compilée en release.
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[\(String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)))] \(message())")
    fflush(stdout)
    #endif
}

#if DEBUG
import AppKit

/// Développement uniquement : `macland --snapshots <dossier>` capture les fenêtres de l'app en PNG
/// (une app peut capturer ses propres fenêtres sans permission d'enregistrement d'écran).
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshots"), args.indices.contains(index + 1) else { return nil }
        return URL(filePath: args[index + 1], directoryHint: .isDirectory)
    }

    static func capture(_ window: NSWindow?, name: String) {
        guard let directory, let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }
}
#endif

#if DEBUG
import ImageIO
import UniformTypeIdentifiers

/// Développement uniquement : met en scène l'île sur un faux fond d'écran pour le README (images et GIF).
@MainActor
enum DebugMedia {
    /// Hauteur (pt) conservée sous le haut de l'écran.
    static let cropHeight: CGFloat = 250

    /// Capture la fenêtre de l'île et la pose sur un fond façon macOS, avec la barre des menus.
    static func frame(of window: NSWindow?, notchHeight: CGFloat) -> CGImage? {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let island = rep.cgImage else { return nil }

        let scale = CGFloat(island.width) / view.bounds.width
        let width = island.width
        let height = Int(cropHeight * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Fond d'écran : dégradé bleu nuit → violet → corail.
        let colors = [CGColor(red: 0.16, green: 0.2, blue: 0.48, alpha: 1),
                      CGColor(red: 0.45, green: 0.27, blue: 0.62, alpha: 1),
                      CGColor(red: 0.93, green: 0.52, blue: 0.5, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.55, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: CGFloat(width), y: 0), options: [])

        // Barre des menus translucide.
        let menuBar = notchHeight * scale
        context.setFillColor(CGColor(gray: 1, alpha: 0.18))
        context.fill(CGRect(x: 0, y: CGFloat(height) - menuBar, width: CGFloat(width), height: menuBar))

        // L'île (le haut de la fenêtre = le haut de l'écran).
        context.draw(island, in: CGRect(x: 0, y: CGFloat(height) - CGFloat(island.height),
                                        width: CGFloat(island.width), height: CGFloat(island.height)))
        return context.makeImage()
    }

    static func downscaled(_ image: CGImage, by factor: CGFloat) -> CGImage {
        let width = Int(CGFloat(image.width) / factor), height = Int(CGFloat(image.height) / factor)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        frames.forEach { CGImageDestinationAddImage(destination, $0, frameProperties) }
        CGImageDestinationFinalize(destination)
    }
}
#endif
