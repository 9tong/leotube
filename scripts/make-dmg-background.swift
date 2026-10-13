// Renders the DMG window background. Usage: swift scripts/make-dmg-background.swift out.png scale
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "background.png"
let scale = args.count > 2 ? CGFloat(Double(args[2]) ?? 1) : 1
let size = CGSize(width: 660, height: 420)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Base
NSColor(red: 0.07, green: 0.06, blue: 0.08, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// Soft glows in the icon's palette
func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor) {
    let g = NSGradient(colors: [color, color.withAlphaComponent(0)])!
    g.draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
}
glow(150, 330, 300, NSColor(red: 1.0, green: 0.16, blue: 0.3, alpha: 0.42))
glow(560, 60, 320, NSColor(red: 0.55, green: 0.12, blue: 0.45, alpha: 0.35))
glow(330, 210, 260, NSColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 0.10))

// Title
let para = NSMutableParagraphStyle()
para.alignment = .center
let title = NSAttributedString(string: "LeoTube", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: para,
])
title.draw(in: NSRect(x: 0, y: size.height - 74, width: size.width, height: 40))
let subtitle = NSAttributedString(string: "Drag LeoTube into Applications to install", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.6),
    .paragraphStyle: para,
])
subtitle.draw(in: NSRect(x: 0, y: size.height - 100, width: size.width, height: 20))

// Arrow between the two icon slots (icons sit at x=180 and x=480, y=200 from top)
let arrowY = size.height - 200
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
ctx.setLineWidth(3)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 9])
ctx.move(to: CGPoint(x: 268, y: arrowY))
ctx.addLine(to: CGPoint(x: 384, y: arrowY))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 378, y: arrowY + 11))
ctx.addLine(to: CGPoint(x: 392, y: arrowY))
ctx.addLine(to: CGPoint(x: 378, y: arrowY - 11))
ctx.strokePath()

// Footer
let foot = NSAttributedString(string: "Not affiliated with Google or YouTube", attributes: [
    .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.35),
    .paragraphStyle: para,
])
foot.draw(in: NSRect(x: 0, y: 22, width: size.width, height: 16))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
