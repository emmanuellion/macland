// Génère Resources/AppIcon.icns : swiftc scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
// Gabarit des icônes macOS : carré arrondi continu de 824 pt dans un canevas de 1024, ombre portée douce.
import AppKit
import SwiftUI

struct IslandIcon: View {
    var body: some View {
        ZStack {
            // Fond : dégradé façon fond d'écran macOS.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.36, green: 0.42, blue: 0.98),
                            Color(red: 0.62, green: 0.38, blue: 0.95),
                            Color(red: 0.98, green: 0.52, blue: 0.62),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    // Halo clair en haut, comme une source de lumière.
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.35), .clear],
                                             center: .init(x: 0.3, y: 0.05), startRadius: 0, endRadius: 620))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 24, y: 14)

            // L'île ouverte, accrochée en haut.
            VStack {
                IslandShape()
                    .fill(
                        LinearGradient(colors: [Color(white: 0.1), .black], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        IslandShape().stroke(.white.opacity(0.12), lineWidth: 2)
                    )
                    .frame(width: 600, height: 300)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 36) {
                            // Pochette.
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.35),
                                                              Color(red: 0.95, green: 0.3, blue: 0.55)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 140, height: 140)
                            // Égaliseur.
                            HStack(alignment: .center, spacing: 18) {
                                ForEach([70.0, 130, 95, 150, 60], id: \.self) { height in
                                    Capsule().fill(.white).frame(width: 26, height: height)
                                }
                            }
                            .frame(height: 150)
                        }
                        .padding(.bottom, 56)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                Spacer()
            }
            .frame(width: 824, height: 824)
            .padding(.top, 0)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Bords supérieurs évasés et coins inférieurs arrondis, comme l'encoche.
struct IslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let t: CGFloat = 40
        let b: CGFloat = 90
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

@MainActor
func render() throws {
    let root = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
    let renderer = ImageRenderer(content: IslandIcon())
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("rendu impossible") }

    let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try write(image, pixels: pixels, to: iconset.appending(path: name))
        }
    }
    try write(image, pixels: 1024, to: root.appending(path: "Resources/AppIcon.png"))

    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
    try process.run()
    process.waitUntilExit()
    print(process.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "échec iconutil")
}

func write(_ image: CGImage, pixels: Int, to url: URL) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

MainActor.assumeIsolated { try! render() }
