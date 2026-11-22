#!/usr/bin/env swift
// Hero banner for the README (2400 × 1260): sunset gradient, app icon, title, claim and three framed iPhone screens.
//
// Usage:
//   swift scripts/make-hero.swift <icon.png> <front.png> <middle.png> <back.png> <out.png>
//
// The screens are raw simulator screenshots (e.g. `xcrun simctl io <udid> screenshot`, launched with
// `-uiSeed demo -uiShowcase YES`). The script only frames and arranges them; nothing is fetched from the network.
import AppKit

let args = CommandLine.arguments
guard args.count == 6 else {
    FileHandle.standardError.write("usage: make-hero.swift <icon> <front> <middle> <back> <out>\n".data(using: .utf8)!)
    exit(2)
}
func load(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else { fatalError("cannot read \(path)") }
    return image
}
let icon = load(args[1]), front = load(args[2]), middle = load(args[3]), back = load(args[4])

let width = 2400, height = 1260
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let base = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
let cg = base.cgContext
// Top-left origin, like the screenshots and the layout values below.
cg.translateBy(x: 0, y: CGFloat(height))
cg.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Background: the app's sunset gradient (peach → coral → pink), diagonal.
let gradient = NSGradient(colors: [color(0xFFC3A0), color(0xFF8F73), color(0xFF6FAE)], atLocations: [0, 0.5, 1],
                          colorSpace: .sRGB)!
gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -32)
// Soft light from the top left and faint "snow" dots: winter, but warm.
NSGradient(colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)])!
    .draw(fromCenter: NSPoint(x: 260, y: 160), radius: 0, toCenter: NSPoint(x: 260, y: 160), radius: 900, options: [])
var seed: UInt64 = 0x1CE_C0AC
func random() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<70 {
    let r = 2 + random() * 5
    color(0xFFFFFF, 0.18 + random() * 0.25).setFill()
    NSBezierPath(ovalIn: NSRect(x: random() * CGFloat(width), y: random() * CGFloat(height), width: r, height: r)).fill()
}

// Icon, title, claim.
let iconRect = NSRect(x: 124, y: 214, width: 214, height: 214)
NSGraphicsContext.saveGraphicsState()
let iconShadow = NSShadow(); iconShadow.shadowColor = color(0x7A2A1A, 0.28); iconShadow.shadowBlurRadius = 30
iconShadow.shadowOffset = NSSize(width: 0, height: -12); iconShadow.set()
NSBezierPath(roundedRect: iconRect, xRadius: 48, yRadius: 48).addClip()
icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
NSGraphicsContext.restoreGraphicsState()

let ink = color(0x24131D)
NSAttributedString(string: "IndoorCoach", attributes: [
    .font: NSFont.systemFont(ofSize: 150, weight: .heavy), .foregroundColor: ink, .kern: -3,
]).draw(at: NSPoint(x: 116, y: 468))
let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 10
NSAttributedString(string: "Dein Winter-Coach für die Rolle: Claude plant die Woche, Zwift oder MyWhoosh fahren mit – und jeder Gipfel wird gefeiert.",
                   attributes: [.font: NSFont.systemFont(ofSize: 50, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.88),
                                .paragraphStyle: paragraph])
    .draw(in: NSRect(x: 124, y: 680, width: 820, height: 340))

// Chips: what's new, in the app's pill style.
var chipX: CGFloat = 124
for label in ["Gipfelmomente", "intervals.icu", "Neue Diagramme"] {
    let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .semibold),
                                                              .foregroundColor: ink])
    let size = text.size()
    let chip = NSRect(x: chipX, y: 1040, width: size.width + 44, height: 58)
    color(0xFFFFFF, 0.55).setFill()
    NSBezierPath(roundedRect: chip, xRadius: 29, yRadius: 29).fill()
    text.draw(at: NSPoint(x: chip.minX + 22, y: chip.minY + (58 - size.height) / 2))
    chipX = chip.maxX + 16
}

// Framed phones: black bezel, rounded screen, soft shadow. `x`/`y` = top-left of the device, `h` = device height.
func phone(_ screen: NSImage, x: CGFloat, y: CGFloat, h: CGFloat, tilt: CGFloat = 0) {
    let aspect = screen.size.width / screen.size.height
    let bezel = h * 0.022
    let w = (h - 2 * bezel) * aspect + 2 * bezel
    let device = NSRect(x: x, y: y, width: w, height: h)
    let radius = w * 0.165
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: device.midX, yBy: device.midY); transform.rotate(byDegrees: tilt)
    transform.translateX(by: -device.midX, yBy: -device.midY); transform.concat()
    let shadow = NSShadow(); shadow.shadowColor = color(0x5A1430, 0.38); shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -28); shadow.set()
    color(0x1B1B1F).setFill()
    NSBezierPath(roundedRect: device, xRadius: radius, yRadius: radius).fill()
    NSShadow().set()
    color(0x3A3A40).setStroke()
    let rim = NSBezierPath(roundedRect: device.insetBy(dx: 2, dy: 2), xRadius: radius - 2, yRadius: radius - 2)
    rim.lineWidth = 3; rim.stroke()
    let display = device.insetBy(dx: bezel, dy: bezel)
    NSBezierPath(roundedRect: display, xRadius: radius - bezel, yRadius: radius - bezel).addClip()
    screen.draw(in: display, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
}
phone(back, x: 1905, y: 205, h: 930, tilt: -4)
phone(middle, x: 1500, y: 120, h: 1000, tilt: -2)
phone(front, x: 1040, y: 70, h: 1080)

NSGraphicsContext.current?.flushGraphics()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: args[5]))
print("wrote \(args[5]) (\(width)×\(height))")
