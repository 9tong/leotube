import AppKit
import ImageIO

/// Where everything on the turntable sits, in a fixed 1000 × 760 design space
/// (y pointing down). The view scales the whole stage to fit. The rendered
/// images in Resources/Turntable are built on the same numbers.
enum TurntableGeometry {
    static let size = CGSize(width: 1000, height: 760)
    /// Room around the deck's bitmap for its shadow.
    static let deckMargin: CGFloat = 90

    static let spindle = CGPoint(x: 390, y: 380)
    static let platterRadius: CGFloat = 346
    static let recordRadius: CGFloat = 326
    static let labelRadius: CGFloat = 132
    /// Where the stylus sits at the start and the end of a song.
    static let leadInRadius: CGFloat = 313
    static let leadOutRadius: CGFloat = 156

    static let pivot = CGPoint(x: 845, y: 168)
    static let armLength: CGFloat = 520

    private static var pivotDistance: CGFloat { hypot(pivot.x - spindle.x, pivot.y - spindle.y) }
    private static var directionToSpindle: CGFloat { atan2(spindle.y - pivot.y, spindle.x - pivot.x) }

    /// Arm rotation (0 = pointing straight down, positive = over the record)
    /// that puts the stylus at `radius` from the spindle.
    static func armAngle(radius: CGFloat) -> CGFloat {
        let d = pivotDistance, l = armLength
        let cosine = (d * d + l * l - radius * radius) / (2 * d * l)
        return directionToSpindle - acos(min(max(cosine, -1), 1)) - .pi / 2
    }

    /// Arm rotation for a song position, 0...1.
    static func armAngle(progress: Double) -> CGFloat {
        let p = CGFloat(min(max(progress, 0), 1))
        return armAngle(radius: leadInRadius + (leadOutRadius - leadInRadius) * p)
    }

    static let restAngle: CGFloat = 4.5 * .pi / 180
}

/// The turntable's images. The photographic ones are rendered offline by
/// scripts/render-turntable.swift and lit once: the light stays put while only
/// the label and slight unevenness turn. `static let` makes loading lazy and
/// thread-safe.
enum TurntableArt {
    private static let scale: CGFloat = 1.7
    private typealias G = TurntableGeometry

    static let deck: CGImage = drawDeck()
    static let platter: CGImage = rendered("platter")
    static let record: CGImage = rendered("record")
    static let arm: CGImage = rendered("arm")
    static let armShadow: CGImage = rendered("arm-shadow")
    static let platterMarks: CGImage = drawPlatterMarks()
    static let unevenness: CGImage = drawUnevenness()
    static let labelShade: CGImage = drawLabelShade()
    static let discShadow: CGImage = drawDiscShadow()
    static let spindleCap: CGImage = drawSpindle()

    /// Loads and draws everything ahead of time, off the main thread, so
    /// opening Now Playing doesn't drop frames.
    static func prewarm() {
        Task.detached(priority: .utility) {
            _ = (deck, platter, record, arm, armShadow, platterMarks, unevenness, labelShade, discShadow, spindleCap)
        }
    }

    // Image sizes, shared with the layers that show them.
    static let platterSize = CGSize(width: 712, height: 712)
    static let discSize = CGSize(width: 664, height: 664)
    static let discShadowSize = CGSize(width: 820, height: 820)
    static let armSize = CGSize(width: 180, height: 760)
    static let armShadowSize = CGSize(width: 600, height: 1160)
    /// The pivot's position inside the arm's images.
    static let armPivot = CGPoint(x: 90, y: 185)
    static let armShadowPivot = CGPoint(x: 300, y: 400)
    static let spindleSize = CGSize(width: 30, height: 30)
    static let labelSize = CGSize(width: 264, height: 264)
    static let deckCornerRadius: CGFloat = 54

    private static func rendered(_ name: String) -> CGImage {
        // Decoded now, not on the first frame that shows it.
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        if let url = Bundle.main.url(forResource: name, withExtension: "heic", subdirectory: "Turntable"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, options) {
            return image
        }
        NSLog("[turntable] %@ is missing from the app bundle (build with scripts/build-app.sh)", name)
        return render(CGSize(width: 1, height: 1)) { _ in }
    }

    // MARK: - Helpers

    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [w, w, w, a])!
    }

    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                                CGFloat(hex & 0xFF) / 255, a])!
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
    }

    /// Renders into a bitmap with y pointing down. Shadow offsets ignore the
    /// context's transform, so they go through `shadow(_:dy:blur:color:)`.
    private static func render(_ size: CGSize, scale: CGFloat = scale, _ draw: (CGContext) -> Void) -> CGImage {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()!
    }

    private static func shadow(_ ctx: CGContext, dx: CGFloat = 0, dy: CGFloat, blur: CGFloat, color: CGColor) {
        ctx.setShadow(offset: CGSize(width: dx * scale, height: -dy * scale), blur: blur * scale, color: color)
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private static func conic(_ ctx: CGContext, _ g: CGGradient, center: CGPoint, angle: CGFloat) {
        CGContextDrawConicGradient(ctx, g, center, angle)
    }

    private static func fillCircle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, linear g: CGGradient,
                                   from a: CGPoint, to b: CGPoint) {
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, r)); ctx.clip()
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// Repeatable noise, so the art looks the same every launch.
    private struct Noise {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 40) / CGFloat(1 << 24)
        }
    }

    // MARK: - Deck

    /// The rendered deck with its shadow on the page.
    private static func drawDeck() -> CGImage {
        let m = G.deckMargin
        let size = CGSize(width: G.size.width + m * 2, height: G.size.height + m * 2)
        let image = rendered("deck")
        return render(size) { ctx in
            ctx.saveGState()
            shadow(ctx, dy: 30, blur: 64, color: gray(0, 0.6))
            ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
    }

    // MARK: - Platter and record

    /// Strobe marks around the rim, so you can see the platter turn.
    private static func drawPlatterMarks() -> CGImage {
        render(platterSize) { ctx in
            let c = CGPoint(x: platterSize.width / 2, y: platterSize.height / 2)
            for i in 0..<150 {
                let a = CGFloat(i) / 150 * 2 * .pi, r = G.platterRadius - 8.5
                ctx.setFillColor(gray(0.03, 0.82))
                ctx.fillEllipse(in: circle(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r), 2.1))
            }
        }
    }

    /// Faint unevenness of the grooves: this turns, the glare on them doesn't.
    private static func drawUnevenness() -> CGImage {
        render(discSize, scale: 1) { ctx in
            let c = CGPoint(x: discSize.width / 2, y: discSize.height / 2)
            ctx.addEllipse(in: circle(c, G.recordRadius - 8)); ctx.addEllipse(in: circle(c, G.leadOutRadius)); ctx.clip(using: .evenOdd)
            conic(ctx, gradient([(0, gray(1, 0)), (0.07, gray(1, 0.04)), (0.13, gray(1, 0)), (0.31, gray(1, 0.012)), (0.36, gray(1, 0.045)),
                                 (0.42, gray(1, 0)), (0.63, gray(1, 0.025)), (0.72, gray(1, 0)), (0.84, gray(1, 0.035)), (0.9, gray(1, 0)),
                                 (1, gray(1, 0))]), center: c, angle: 0)
            // A few hairline scuffs.
            var noise = Noise(state: 11)
            ctx.setLineWidth(0.7)
            for _ in 0..<26 {
                let r = G.leadOutRadius + 12 + noise.next() * 140, a = noise.next() * 2 * .pi, span = 0.04 + noise.next() * 0.12
                ctx.setStrokeColor(gray(1, 0.03 + noise.next() * 0.06))
                ctx.addArc(center: c, radius: r, startAngle: a, endAngle: a + span, clockwise: false); ctx.strokePath()
            }
        }
    }

    /// Light falling across the paper label, which doesn't turn either.
    private static func drawLabelShade() -> CGImage {
        render(labelSize, scale: 2) { ctx in
            let c = CGPoint(x: labelSize.width / 2, y: labelSize.height / 2)
            fillCircle(ctx, c, G.labelRadius - 1, linear: gradient([(0, gray(1, 0.13)), (0.45, gray(0, 0)), (1, gray(0, 0.26))]),
                       from: CGPoint(x: 40, y: 20), to: CGPoint(x: 225, y: 245))
            // The label is pressed into the vinyl.
            ctx.setLineWidth(1.6)
            ctx.saveGState()
            ctx.addEllipse(in: circle(c, G.labelRadius - 0.8)); ctx.setLineWidth(1.8); ctx.replacePathWithStrokedPath(); ctx.clip()
            ctx.drawLinearGradient(gradient([(0, gray(0, 0.75)), (0.5, gray(0, 0.35)), (1, gray(1, 0.28))]), start: CGPoint(x: 40, y: 20),
                                   end: CGPoint(x: 225, y: 245), options: [])
            ctx.restoreGState()
            // Ring left by the pressing.
            ctx.setStrokeColor(gray(0, 0.22)); ctx.setLineWidth(1); ctx.strokeEllipse(in: circle(c, 41))
            ctx.setStrokeColor(gray(1, 0.14)); ctx.strokeEllipse(in: circle(c, 42.1))
        }
    }

    private static func drawDiscShadow() -> CGImage {
        render(discShadowSize, scale: 0.5) { ctx in
            let c = CGPoint(x: discShadowSize.width / 2, y: discShadowSize.height / 2)
            let edge = G.recordRadius / (discShadowSize.width / 2)
            ctx.drawRadialGradient(gradient([(0, gray(0, 0.85)), (edge * 0.93, gray(0, 0.8)), (edge, gray(0, 0.5)), (edge * 1.08, gray(0, 0.16)), (1, gray(0, 0))]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: discShadowSize.width / 2, options: [])
        }
    }

    /// The round label in the middle of the record, with the song's artwork.
    static func label(artwork: CGImage?) -> CGImage {
        render(labelSize, scale: 2) { ctx in
            let c = CGPoint(x: labelSize.width / 2, y: labelSize.height / 2)
            let r = G.labelRadius - 1
            ctx.saveGState()
            ctx.addEllipse(in: circle(c, r)); ctx.clip()
            if let artwork {
                let aw = CGFloat(artwork.width), ah = CGFloat(artwork.height)
                let k = max(labelSize.width / aw, labelSize.height / ah)
                ctx.translateBy(x: 0, y: labelSize.height); ctx.scaleBy(x: 1, y: -1)
                ctx.draw(artwork, in: CGRect(x: (labelSize.width - aw * k) / 2, y: (labelSize.height - ah * k) / 2, width: aw * k, height: ah * k))
            } else {
                ctx.drawLinearGradient(gradient([(0, rgb(0xFF2952)), (1, rgb(0xFF6B45))]), start: .zero,
                                       end: CGPoint(x: labelSize.width, y: labelSize.height), options: [])
            }
            ctx.restoreGState()
            ctx.setFillColor(gray(0.05)); ctx.fillEllipse(in: circle(c, 8))
        }
    }

    private static func drawSpindle() -> CGImage {
        render(spindleSize, scale: 3) { ctx in
            let c = CGPoint(x: 15, y: 15)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 4, height: -6), blur: 8, color: gray(0, 0.6))
            ctx.setFillColor(rgb(0xB8BBC0)); ctx.fillEllipse(in: circle(c, 7))
            ctx.restoreGState()
            fillCircle(ctx, c, 7, linear: gradient([(0, gray(1)), (0.5, rgb(0xC3C6CB)), (1, rgb(0x6E7177))]),
                       from: CGPoint(x: 9, y: 9), to: CGPoint(x: 21, y: 21))
        }
    }
}
