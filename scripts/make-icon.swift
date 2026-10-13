// Renders the LeoTube app icon (1024×1024 PNG). Usage: swift scripts/make-icon.swift out.png
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// macOS icon grid: 824pt squircle centered on a 1024 canvas.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.35))
ctx.addPath(shape)
ctx.setFillColor(color(0.9, 0.1, 0.25))
ctx.fillPath()
ctx.restoreGState()

// Background gradient
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [color(1.0, 0.36, 0.22), color(1.0, 0.12, 0.34), color(0.62, 0.06, 0.42)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

// Soft glow blobs
for (x, y, r, a) in [(0.28, 0.78, 360.0, 0.35), (0.8, 0.22, 420.0, 0.25)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    let g = CGGradient(colorsSpace: cs, colors: [color(1, 0.85, 0.7, a), color(1, 0.85, 0.7, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: size * x, y: size * y), startRadius: 0,
                           endCenter: CGPoint(x: size * x, y: size * y), endRadius: r, options: [])
}

// Glass disc
let disc = CGRect(x: size / 2 - 250, y: size / 2 - 250, width: 500, height: 500)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: color(0.3, 0, 0.1, 0.35))
ctx.addEllipse(in: disc)
ctx.setFillColor(color(1, 1, 1, 0.18))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: disc)
ctx.clip()
let sheen = CGGradient(colorsSpace: cs, colors: [color(1, 1, 1, 0.5), color(1, 1, 1, 0.05)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: disc.midX, y: disc.maxY), end: CGPoint(x: disc.midX, y: disc.midY), options: [])
ctx.restoreGState()
ctx.addEllipse(in: disc.insetBy(dx: 2, dy: 2))
ctx.setStrokeColor(color(1, 1, 1, 0.55))
ctx.setLineWidth(4)
ctx.strokePath()

// Play triangle with rounded corners
let tri = CGMutablePath()
let cx = size / 2 + 22, cy = size / 2
tri.move(to: CGPoint(x: cx - 95, y: cy + 150))
tri.addLine(to: CGPoint(x: cx + 150, y: cy))
tri.addLine(to: CGPoint(x: cx - 95, y: cy - 150))
tri.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: color(0.4, 0, 0.1, 0.4))
ctx.addPath(tri)
ctx.setLineJoin(.round)
ctx.setLineWidth(56)
ctx.setStrokeColor(color(1, 1, 1))
ctx.setFillColor(color(1, 1, 1))
ctx.drawPath(using: .fillStroke)
ctx.restoreGState()

// Top highlight on the squircle edge
ctx.addPath(shape)
ctx.setStrokeColor(color(1, 1, 1, 0.22))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
