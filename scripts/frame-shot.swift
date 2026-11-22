#!/usr/bin/env swift
// Frames a raw simulator screenshot as an iPhone (black bezel, rounded display) on a transparent background,
// in the size of the README screenshots (height 1322 px).
//
// Usage: swift scripts/frame-shot.swift <screenshot.png> <out.png> [height]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let screen = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: frame-shot.swift <screenshot> <out> [height]\n".data(using: .utf8)!)
    exit(2)
}
let height = args.count > 3 ? Int(args[3]) ?? 1322 : 1322
let h = CGFloat(height)
let bezel = (h * 0.022).rounded()
let aspect = screen.size.width / screen.size.height
let w = ((h - 2 * bezel) * aspect + 2 * bezel).rounded()
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: height, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let base = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
let cg = base.cgContext
cg.translateBy(x: 0, y: h)
cg.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

let device = NSRect(x: 0, y: 0, width: w, height: h)
let radius = w * 0.165
NSColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 1).setFill()
NSBezierPath(roundedRect: device, xRadius: radius, yRadius: radius).fill()
NSColor(srgbRed: 0x3A / 255, green: 0x3A / 255, blue: 0x40 / 255, alpha: 1).setStroke()
let rim = NSBezierPath(roundedRect: device.insetBy(dx: 1.5, dy: 1.5), xRadius: radius - 1.5, yRadius: radius - 1.5)
rim.lineWidth = 3
rim.stroke()
let display = device.insetBy(dx: bezel, dy: bezel)
NSBezierPath(roundedRect: display, xRadius: radius - bezel, yRadius: radius - bezel).addClip()
screen.draw(in: display, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

NSGraphicsContext.current?.flushGraphics()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) (\(Int(w))×\(height))")
