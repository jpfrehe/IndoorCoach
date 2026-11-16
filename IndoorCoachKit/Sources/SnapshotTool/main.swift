// Renders the main screens and the app icon to PNG (macOS only) – a visual check without an iOS simulator.
// Usage: swift run SnapshotTool <output-dir> [<app-icon.png>]
#if os(macOS)
import AppKit
import IndoorCoachKit
import SwiftUI

@MainActor
func render<V: View>(_ view: V, to url: URL, scale: CGFloat = 2, dark: Bool = false) throws {
    let wrapped = view
        .background(dark ? Color.black : Color(red: 0.95, green: 0.95, blue: 0.97))
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: wrapped)
    renderer.scale = scale
    guard let image = renderer.cgImage else { throw NSError(domain: "render", code: 1) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "png", code: 2) }
    try data.write(to: url)
    print("✓ \(url.lastPathComponent) \(image.width)×\(image.height)")
}

@MainActor
func run() throws {
    let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "snapshots")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let (container, model) = AppEnvironment.makePreviewModel()
    let scenes = SnapshotScenes.scenes(model: model, container: container)
    for scene in scenes {
        try render(scene.view, to: out.appendingPathComponent("\(scene.name).png"))
    }
    if let first = scenes.first {
        try render(first.view, to: out.appendingPathComponent("\(first.name)-dark.png"), dark: true)
    }
    if CommandLine.arguments.count > 2 {
        let renderer = ImageRenderer(content: SnapshotScenes.appIcon)
        renderer.scale = 1
        if let cg = renderer.cgImage,
           let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            print("✓ App-Icon")
        }
    }
}

MainActor.assumeIsolated {
    do { try run() } catch { print("Fehler: \(error)"); exit(1) }
}
#else
print("SnapshotTool läuft nur auf macOS.")
#endif
