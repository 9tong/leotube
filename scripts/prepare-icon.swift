// Turns a flattened icon render (rounded square on an opaque background) into a
// 1024×1024 macOS app icon with transparency, following the standard icon grid.
// Usage: swift scripts/prepare-icon.swift input.png output.png
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: prepare-icon.swift input.png output.png"); exit(1)
}

// Read pixels to locate the rounded square (anything clearly darker than the backdrop).
let w = cg.width, h = cg.height
let rgb = CGColorSpaceCreateDeviceRGB()
var px = [UInt8](repeating: 0, count: w * h * 4)
let readCtx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: rgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
readCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func luma(_ x: Int, _ y: Int) -> Double {
    let i = (y * w + x) * 4
    return (0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])) / 255
}
let midX = w / 2, midY = h / 2
let isShape: (Double) -> Bool = { $0 < 0.55 }
let left = (0..<w).first { isShape(luma($0, midY)) } ?? 0
let right = (0..<w).reversed().first { isShape(luma($0, midY)) } ?? w - 1
let top = (0..<h).first { isShape(luma(midX, $0)) } ?? 0
let bottom = (0..<h).reversed().first { isShape(luma(midX, $0)) } ?? h - 1
print("shape bounds: x \(left)…\(right), y \(top)…\(bottom)")

// Trim a couple of pixels so no light halo from the original backdrop remains.
let trim = 6
let crop = CGRect(x: left + trim, y: top + trim, width: right - left - 2 * trim, height: bottom - top - 2 * trim)
guard let cropped = cg.cropping(to: crop) else { exit(1) }

// Compose onto the 1024 macOS grid: 824pt body, continuous corners, soft drop shadow.
let size: CGFloat = 1024, body: CGFloat = 824
let rect = CGRect(x: (size - body) / 2, y: (size - body) / 2 + 6, width: body, height: body)
let radius = body * 0.245
let out = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).cgPath

out.saveGState()
out.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.32))
out.addPath(path)
out.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
out.fillPath()
out.restoreGState()

out.saveGState()
out.addPath(path)
out.clip()
out.interpolationQuality = .high
out.draw(cropped, in: rect)
out.restoreGState()

let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
