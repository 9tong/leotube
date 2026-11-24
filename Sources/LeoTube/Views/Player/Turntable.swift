import AppKit
import SwiftUI
import YTMusicKit

/// A record player that follows playback: the record turns while music plays,
/// the stylus tracks the song's position, the arm moves off the record when
/// playback stops, and changing songs changes the record.
struct Turntable: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let aspectRatio = TurntableGeometry.size.width / TurntableGeometry.size.height

    var body: some View {
        let p = app.player
        TurntableRepresentable(state: TurntableState(
            trackID: p.current?.id,
            artworkURL: p.current?.artwork.url(size: 544),
            nextArtworkURL: p.upNext.first?.artwork.url(size: 544),
            order: p.index,
            isPlaying: p.isPlaying,
            isBuffering: p.isBuffering,
            isAd: p.isAd,
            time: p.timeAnchor.time,
            date: p.timeAnchor.date,
            duration: p.duration,
            isVisible: app.isWindowVisible,
            reduceMotion: reduceMotion))
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

struct TurntableState {
    var trackID: String?
    var artworkURL: URL?
    var nextArtworkURL: URL?
    /// Position in the queue; tells a step back from a step forward.
    var order = -1
    var isPlaying = false
    var isBuffering = false
    var isAd = false
    var time: Double = 0
    var date = Date.distantPast
    var duration: Double = 0
    var isVisible = true
    var reduceMotion = false

    func position(at now: Date) -> Double {
        let t = isPlaying && !isBuffering ? time + now.timeIntervalSince(date) : time
        return duration > 0 ? min(max(t, 0), duration) : max(t, 0)
    }
}

private struct TurntableRepresentable: NSViewRepresentable {
    var state: TurntableState

    func makeNSView(context: Context) -> TurntableNSView { TurntableNSView() }
    func updateNSView(_ view: TurntableNSView, context: Context) { view.apply(state) }
}

/// All the motion is Core Animation on prerendered bitmaps: the main thread
/// only steps in when something changes (play, pause, seek, next song), never
/// per frame.
final class TurntableNSView: NSView {
    private typealias G = TurntableGeometry
    private typealias A = TurntableArt

    private let stage = CALayer()
    private let discs = CALayer()
    private let platter = Spinner(image: A.platterMarks, size: A.platterSize)
    private let led = CALayer()
    private var disc: Disc?
    // Lifting (scale, shadow distance) and swinging (rotation) are on separate
    // layers so each can be animated and interrupted on its own.
    private let armLift = CALayer()
    private let arm = CALayer()
    private let armShadowLift = CALayer()
    private let armShadow = CALayer()

    private var state = TurntableState()
    /// The song whose record is on the platter (nil = none yet).
    private var discTrack: String?
    private var discOrder = -1
    private var swapEnds: CFTimeInterval = 0
    private enum ArmState { case resting, moving, tracking }
    private var armState = ArmState.resting
    /// What the running choreography is heading for.
    private var goal: Goal?
    private var choreography: Task<Void, Never>?

    private struct Goal: Equatable {
        var track: String?
        var engaged: Bool
        var spinning: Bool
        var active: Bool
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Layers

    private func build() {
        func image(_ cg: CGImage, _ size: CGSize, at p: CGPoint) -> CALayer {
            let l = CALayer()
            l.contents = cg
            l.bounds.size = size
            l.position = p
            l.minificationFilter = .trilinear
            return l
        }
        stage.bounds.size = G.size
        stage.isGeometryFlipped = true
        layer?.addSublayer(stage)

        let m = G.deckMargin
        stage.addSublayer(image(A.deck, CGSize(width: G.size.width + 2 * m, height: G.size.height + 2 * m),
                                at: CGPoint(x: G.size.width / 2, y: G.size.height / 2)))
        stage.addSublayer(image(A.platter, A.platterSize, at: G.spindle))
        platter.layer.position = G.spindle
        stage.addSublayer(platter.layer)
        stage.addSublayer(image(A.spindleCap, A.spindleSize, at: G.spindle))
        stage.addSublayer(discs)

        led.bounds.size = CGSize(width: 14, height: 14)
        led.cornerRadius = 7
        led.position = CGPoint(x: 944, y: 700)
        led.backgroundColor = NSColor(Theme.accent).cgColor
        led.shadowColor = NSColor(Theme.accent).cgColor
        led.shadowRadius = 8
        led.shadowOffset = .zero
        led.shadowOpacity = 0
        led.opacity = 0.25
        stage.addSublayer(led)

        // The shadow stays on the deck.
        let shadowClip = CALayer()
        shadowClip.frame = CGRect(x: 0, y: 0, width: G.size.width, height: G.size.height - 10)
        shadowClip.cornerRadius = A.deckCornerRadius
        shadowClip.masksToBounds = true
        stage.addSublayer(shadowClip)
        func place(_ part: CALayer, in lift: CALayer, on parent: CALayer, _ cg: CGImage, _ size: CGSize, pivot: CGPoint) {
            lift.position = G.pivot
            part.contents = cg
            part.bounds.size = size
            part.anchorPoint = CGPoint(x: pivot.x / size.width, y: pivot.y / size.height)
            part.minificationFilter = .trilinear
            part.transform = CATransform3DMakeRotation(G.restAngle, 0, 0, 1)
            lift.addSublayer(part)
            parent.addSublayer(lift)
        }
        place(armShadow, in: armShadowLift, on: shadowClip, A.armShadow, A.armShadowSize, pivot: A.armShadowPivot)
        place(arm, in: armLift, on: stage, A.arm, A.armSize, pivot: A.armPivot)
        armShadowLift.position = Self.shadowPosition(lifted: false)
        armShadowLift.opacity = Self.shadowOpacity(lifted: false)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let k = min(bounds.width / G.size.width, bounds.height / G.size.height)
        stage.position = CGPoint(x: bounds.midX, y: bounds.midY)
        stage.transform = CATransform3DMakeScale(k, k, 1)
        CATransaction.commit()
    }

    // Core Animation drops animations from layers that leave the window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            choreography?.cancel()
            goal = nil
        } else {
            apply(state)
        }
    }

    // MARK: - State

    func apply(_ new: TurntableState) {
        let old = state
        state = new
        guard window != nil else { return }
        prefetch(new.nextArtworkURL)

        if discTrack == nil, let id = new.trackID {
            // First record: it's simply there.
            install(Disc(artworkURL: new.artworkURL), track: id)
        } else if new.trackID == discTrack, old.artworkURL != new.artworkURL {
            disc?.loadArtwork(new.artworkURL)
        }

        // A short rebuffer in the middle of a song doesn't lift the arm.
        let wasTracking = armState == .tracking && new.trackID == discTrack
        let engaged = new.isPlaying && !new.isAd && new.duration > 0 && (!new.isBuffering || wasTracking)
        let next = Goal(track: new.trackID, engaged: engaged, spinning: new.isPlaying, active: new.isVisible)
        if next != goal {
            let wasActive = goal?.active ?? true
            goal = next
            choreograph(snap: next.active != wasActive)
        } else if armState == .tracking {
            // Same song, still playing: a seek, or the position or duration
            // was corrected.
            let moved = abs(old.position(at: .now) - new.position(at: .now))
            let changed = old.date != new.date || old.duration != new.duration || old.isBuffering != new.isBuffering
            if moved > 3 { choreograph(reseat: true) } else if changed { track(glide: 0.5) }
        }
    }

    private func prefetch(_ url: URL?) {
        guard let url, ImagePipeline.shared.cached(url) == nil else { return }
        Task { _ = await ImagePipeline.shared.image(for: url) }
    }

    /// Brings the turntable to the current goal, one physical step at a time.
    /// Every step starts from where things are on screen, so a newer call can
    /// take over at any point without a jump.
    private func choreograph(snap: Bool = false, reseat: Bool = false) {
        choreography?.cancel()
        guard let goal else { return }
        guard goal.active else {
            // Nobody can see it: stop spending energy.
            platter.stopNow(); disc?.spinner.stopNow()
            freezeArm()
            return
        }
        choreography = Task { @MainActor [weak self] in
            func pause(_ s: Double) async -> Bool {
                try? await Task.sleep(for: .seconds(s))
                return !Task.isCancelled
            }
            guard let self else { return }
            self.setLED(goal.spinning)

            if let id = goal.track, id != self.discTrack {
                if self.armState != .resting {
                    self.setLift(true, duration: 0.18)
                    guard await pause(0.12) else { return }
                    self.swing(to: G.restAngle, duration: 0.5)
                    guard await pause(0.38) else { return }
                    self.setLift(false, duration: 0.22)
                    self.armState = .resting
                }
                self.spin(false)
                self.swapRecord(to: id)
            }
            let wait = self.swapEnds - CACurrentMediaTime()
            if wait > 0 { guard await pause(wait) else { return } }
            self.spin(goal.spinning, snap: snap)

            if goal.engaged {
                if snap {
                    self.armState = .tracking
                    self.track(glide: 0)
                } else if self.armState != .tracking || reseat {
                    self.armState = .moving
                    self.setLift(true, duration: 0.2)
                    guard await pause(0.14) else { return }
                    let seconds = reseat ? 0.45 : 0.75
                    self.swing(to: self.armAngle(after: seconds + 0.2), duration: seconds)
                    guard await pause(seconds) else { return }
                    self.setLift(false, duration: 0.28)
                    guard await pause(0.2) else { return }
                    self.armState = .tracking
                    self.track(glide: 0.15)
                }
            } else if self.armState != .resting {
                self.armState = .moving
                self.setLift(true, duration: 0.2)
                guard await pause(0.14) else { return }
                self.swing(to: G.restAngle, duration: 0.8)
                guard await pause(0.74) else { return }
                self.setLift(false, duration: 0.3)
                self.armState = .resting
            }
        }
    }

    // MARK: - Arm

    private static func shadowPosition(lifted: Bool) -> CGPoint {
        // The rendered shadow already falls to the side.
        CGPoint(x: G.pivot.x + (lifted ? 12 : 0), y: G.pivot.y + (lifted ? 17 : 0))
    }

    private static func shadowOpacity(lifted: Bool) -> Float { lifted ? 0.6 : 0.9 }

    private func armAngle(after seconds: Double = 0) -> CGFloat {
        guard state.duration > 0 else { return G.armAngle(progress: 0) }
        let t = state.position(at: Date.now.addingTimeInterval(seconds))
        return G.armAngle(progress: t / state.duration)
    }

    private var currentArmAngle: CGFloat {
        ((arm.presentation() ?? arm).value(forKeyPath: "transform.rotation.z") as? NSNumber).map { CGFloat($0.doubleValue) } ?? G.restAngle
    }

    private func animateArm(_ make: () -> CAAnimation, to angle: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in [arm, armShadow] {
            part.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            part.add(make(), forKey: "swing")
        }
        CATransaction.commit()
    }

    private func swing(to angle: CGFloat, duration: Double) {
        let from = currentArmAngle
        animateArm({
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = from
            a.toValue = angle
            a.duration = state.reduceMotion ? 0.01 : duration
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.15, 1)
            return a
        }, to: angle)
    }

    /// Lets the stylus ride the groove until the end of the song.
    private func track(glide: Double) {
        guard state.duration > 0 else { return }
        let now = Date.now
        let start = state.position(at: now)
        let moving = state.isPlaying && !state.isBuffering
        let remaining = max(state.duration - start, 0)
        let from = currentArmAngle
        guard moving, remaining > 0.1 else {
            swing(to: G.armAngle(progress: start / state.duration), duration: max(glide, 0.01))
            return
        }
        // Ease a small correction in over `glide` seconds, then follow the groove.
        let glide = min(glide, remaining / 2)
        var points: [(t: Double, angle: CGFloat)] = [(0, glide > 0 ? from : G.armAngle(progress: start / state.duration))]
        for i in 0...48 {
            let t = glide + (remaining - glide) * Double(i) / 48
            if t > 0 { points.append((t, G.armAngle(progress: (start + t) / state.duration))) }
        }
        let values = points.map(\.angle), times = points.map { NSNumber(value: $0.t / remaining) }
        animateArm({
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            a.values = values
            a.keyTimes = times
            a.duration = remaining
            a.calculationMode = .linear
            return a
        }, to: values.last ?? from)
    }

    private func freezeArm() {
        let angle = currentArmAngle
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in [arm, armShadow] {
            part.removeAnimation(forKey: "swing")
            part.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }
        // Whatever step was running won't finish; end up with the arm down.
        for l in [armLift, armShadowLift] { l.removeAllAnimations() }
        armLift.transform = CATransform3DIdentity
        armShadowLift.position = Self.shadowPosition(lifted: false)
        armShadowLift.opacity = Self.shadowOpacity(lifted: false)
        CATransaction.commit()
        if armState == .moving { armState = .tracking }
    }

    private func setLift(_ up: Bool, duration: Double) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: up ? .easeOut : .easeInEaseOut))
        armLift.transform = up ? CATransform3DMakeScale(1.022, 1.022, 1) : CATransform3DIdentity
        armShadowLift.position = Self.shadowPosition(lifted: up)
        armShadowLift.opacity = Self.shadowOpacity(lifted: up)
        CATransaction.commit()
    }

    private func setLED(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        led.opacity = on ? 1 : 0.25
        led.shadowOpacity = on ? 0.9 : 0
        CATransaction.commit()
    }

    // MARK: - Debugging

    var debugDescriptionOfMotion: String {
        let deg = { (a: CGFloat) in Double(a * 180 / .pi) }
        return String(format: "arm=%.2f° (%@) platter=%.0f° lift=%.3f discs=%d", deg(currentArmAngle), "\(armState)", deg(platter.angle),
                      ((armLift.presentation() ?? armLift).value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1,
                      discs.sublayers?.count ?? 0)
    }

    func debugSnapshot(to url: URL) {
        let pad: CGFloat = 60
        let w = Int(bounds.width + pad * 2), h = Int(bounds.height + pad * 2)
        guard w > 0, let layer, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.25, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: pad, y: pad)
        (layer.presentation() ?? layer).render(in: ctx)
        guard let image = ctx.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: - Record

    private func spin(_ on: Bool, snap: Bool = false) {
        let on = on && !state.reduceMotion
        platter.set(on, snap: snap)
        disc?.spinner.set(on, snap: snap)
    }

    private func install(_ new: Disc, track: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        new.layer.position = G.spindle
        discs.addSublayer(new.layer)
        CATransaction.commit()
        disc = new
        discTrack = track
        discOrder = state.order
    }

    /// Next: the old record lifts off and slides away to the left, and the new
    /// one is set down from above. Previous plays the same scene backwards.
    private func swapRecord(to track: String) {
        let back = state.order >= 0 && state.order < discOrder
        let outgoing = disc
        install(Disc(artworkURL: state.artworkURL), track: track)
        guard let incoming = disc else { return }
        let now = CACurrentMediaTime()
        if state.reduceMotion {
            incoming.fade(from: 0, to: 1, duration: 0.3)
            outgoing?.fade(from: 1, to: 0, duration: 0.3)
            remove(outgoing, after: 0.35)
            swapEnds = now + 0.3
            return
        }
        let shelf = CGPoint(x: G.spindle.x - 640, y: G.spindle.y - 10)
        let above = CGPoint(x: G.spindle.x, y: G.spindle.y - 26)
        if back {
            // The current record goes up towards the viewer; on top while it does.
            if let outgoing { outgoing.layer.zPosition = 1 }
            outgoing?.leave(to: above, height: 1.22, fade: 0.3...1, duration: 0.44)
            incoming.arrive(from: shelf, height: 1.07, delay: 0.26, fadeIn: 0.22, duration: 0.82)
        } else {
            outgoing?.leave(to: shelf, height: 1.07, fade: 0.72...1, duration: 0.6)
            incoming.arrive(from: above, height: 1.22, delay: 0.42, fadeIn: 0.24, duration: 0.72)
        }
        remove(outgoing, after: 0.7)
        swapEnds = now + 1.1
    }

    private func remove(_ old: Disc?, after seconds: Double) {
        guard let old else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            old.layer.removeFromSuperlayer()
        }
    }
}

// MARK: - Parts

/// A layer that turns with the inertia of a real platter when it starts and
/// stops. Slower than a real record (one turn every 5 seconds): at 33⅓ rpm the
/// label is a distracting blur next to the controls.
private final class Spinner {
    let layer = CALayer()
    private static let speed: CGFloat = 2 * .pi / 5
    private static let rampUp: Double = 1.5
    private static let rampDown: Double = 1.6

    private var on = false
    private var rampStart: CFTimeInterval = 0
    private var rampDuration: Double = 0
    private var v0: CGFloat = 0
    private var v1: CGFloat = 0

    init(image: CGImage, size: CGSize) {
        layer.contents = image
        layer.bounds.size = size
        layer.minificationFilter = .trilinear
    }

    var angle: CGFloat {
        ((layer.presentation() ?? layer).value(forKeyPath: "transform.rotation.z") as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    }

    private var velocity: CGFloat {
        guard rampDuration > 0 else { return v1 }
        let x = min(max((CACurrentMediaTime() - rampStart) / rampDuration, 0), 1)
        return v0 + (v1 - v0) * CGFloat(x)
    }

    func set(_ on: Bool, snap: Bool = false) {
        guard on != self.on else { return }
        self.on = on
        let target = on ? Self.speed : 0
        let full = on ? Self.rampUp : Self.rampDown
        ramp(to: target, duration: snap ? 0 : full * Double(abs(target - velocity) / Self.speed))
    }

    func stopNow() {
        on = false
        ramp(to: 0, duration: 0)
    }

    /// Constant acceleration from the current speed to `target`, continuing at
    /// that speed. A quadratic is exactly a cubic Bézier with these controls.
    private func ramp(to target: CGFloat, duration: Double) {
        let start = angle, from = velocity, now = CACurrentMediaTime()
        let distance = (from + target) / 2 * CGFloat(duration)
        let end = start + distance
        (v0, v1, rampStart, rampDuration) = (from, target, now, duration)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.transform = CATransform3DMakeRotation(end, 0, 0, 1)
        let local = layer.convertTime(now, from: nil)
        if duration > 0.01, distance > 0.0001 {
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = start
            a.toValue = end
            a.duration = duration
            let t = CGFloat(duration)
            a.timingFunction = CAMediaTimingFunction(controlPoints: 1 / 3, Float(from * t / (3 * distance)),
                                                     2 / 3, Float(1 - target * t / (3 * distance)))
            a.beginTime = local
            a.fillMode = .backwards
            layer.add(a, forKey: "ramp")
        }
        if target > 0 {
            let s = CABasicAnimation(keyPath: "transform.rotation.z")
            s.fromValue = end
            s.toValue = end + 2 * .pi
            s.duration = Double(2 * .pi / target)
            s.repeatCount = .infinity
            s.beginTime = local + duration
            layer.add(s, forKey: "spin")
        }
        CATransaction.commit()
    }
}

/// One record: vinyl and label turn, the light on it and its shadow don't.
private final class Disc {
    let layer = CALayer()
    let spinner = Spinner(image: TurntableArt.unevenness, size: TurntableArt.discSize)
    private let body = CALayer()
    private let shadow = CALayer()
    private let label = CALayer()
    /// The platter's spindle poking through the hole; only while the record
    /// lies on the platter.
    private let spindle = CALayer()
    private var artworkTask: Task<Void, Never>?

    init(artworkURL: URL?) {
        shadow.contents = TurntableArt.discShadow
        shadow.bounds.size = TurntableArt.discShadowSize
        shadow.position = CGPoint(x: 3, y: 5)
        shadow.opacity = 0.6
        layer.addSublayer(shadow)
        layer.addSublayer(body)

        let vinyl = CALayer()
        vinyl.contents = TurntableArt.record
        vinyl.bounds.size = TurntableArt.discSize
        vinyl.minificationFilter = .trilinear
        body.addSublayer(vinyl)
        body.addSublayer(spinner.layer)
        label.bounds.size = TurntableArt.labelSize
        label.position = CGPoint(x: TurntableArt.discSize.width / 2, y: TurntableArt.discSize.height / 2)
        label.minificationFilter = .trilinear
        spinner.layer.addSublayer(label)

        let shade = CALayer()
        shade.contents = TurntableArt.labelShade
        shade.bounds.size = TurntableArt.labelSize
        shade.minificationFilter = .trilinear
        body.addSublayer(shade)
        spindle.contents = TurntableArt.spindleCap
        spindle.bounds.size = TurntableArt.spindleSize
        spindle.minificationFilter = .trilinear
        body.addSublayer(spindle)

        label.contents = TurntableArt.label(artwork: nil)
        loadArtwork(artworkURL)
    }

    func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        guard let url else { return }
        func bake(_ image: NSImage) -> CGImage? {
            image.cgImage(forProposedRect: nil, context: nil, hints: nil).map { TurntableArt.label(artwork: $0) }
        }
        if let image = ImagePipeline.shared.cached(url), let cg = bake(image) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            label.contents = cg
            CATransaction.commit()
            return
        }
        artworkTask = Task { @MainActor [weak self] in
            guard let image = await ImagePipeline.shared.image(for: url), !Task.isCancelled, let cg = bake(image) else { return }
            self?.label.contents = cg
        }
    }

    func fade(from: Float, to: Float, duration: Double) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        layer.opacity = to
        layer.add(a, forKey: "fade")
    }

    private static let glide = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.3)
    private static let settle = CAMediaTimingFunction(controlPoints: 0.35, 0.25, 0.15, 1)

    private func add(_ keyPath: String, to target: CALayer, from: Any?, to value: Any?, begin: Double, duration: Double,
                     timing: CAMediaTimingFunction) {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = value
        a.beginTime = target.convertTime(CACurrentMediaTime(), from: nil) + begin
        a.duration = duration
        a.timingFunction = timing
        a.fillMode = .both
        a.isRemovedOnCompletion = false
        target.add(a, forKey: keyPath)
    }

    /// How the shadow looks with the record held `height` above the platter.
    private static func shadowPosition(_ height: CGFloat) -> CGPoint {
        CGPoint(x: 3 + (height - 1) * 110, y: 5 + (height - 1) * 190)
    }

    private func lift(from: CGFloat, to: CGFloat, begin: Double, duration: Double, timing: CAMediaTimingFunction) {
        add("transform.scale", to: body, from: from, to: to, begin: begin, duration: duration, timing: timing)
        add("position", to: shadow, from: NSValue(point: Self.shadowPosition(from)), to: NSValue(point: Self.shadowPosition(to)),
            begin: begin, duration: duration, timing: timing)
        add("opacity", to: shadow, from: 0.6 - (from - 1) * 1.2, to: 0.6 - (to - 1) * 1.2, begin: begin, duration: duration, timing: timing)
    }

    func leave(to point: CGPoint, height: CGFloat, fade: ClosedRange<Double>, duration: Double) {
        // Interrupted while still arriving: carry on from where it is.
        let p = layer.presentation() ?? layer
        let scale = ((body.presentation() ?? body).value(forKeyPath: "transform.scale") as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
        let opacity = p.opacity
        let spindleOpacity = (spindle.presentation() ?? spindle).opacity
        add("opacity", to: spindle, from: spindleOpacity, to: 0, begin: 0, duration: 0.1, timing: CAMediaTimingFunction(name: .linear))
        lift(from: scale, to: height, begin: 0, duration: duration * 0.6, timing: CAMediaTimingFunction(name: .easeOut))
        add("position", to: layer, from: NSValue(point: p.position), to: NSValue(point: point), begin: 0, duration: duration, timing: Self.glide)
        add("opacity", to: layer, from: opacity, to: 0, begin: duration * fade.lowerBound,
            duration: duration * (fade.upperBound - fade.lowerBound), timing: CAMediaTimingFunction(name: .linear))
    }

    func arrive(from point: CGPoint, height: CGFloat, delay: Double, fadeIn: Double, duration: Double) {
        lift(from: height, to: 1, begin: delay, duration: duration, timing: Self.settle)
        add("position", to: layer, from: NSValue(point: point), to: NSValue(point: TurntableGeometry.spindle),
            begin: delay, duration: duration, timing: Self.settle)
        add("opacity", to: layer, from: 0, to: 1, begin: delay, duration: duration * fadeIn, timing: CAMediaTimingFunction(name: .easeOut))
        add("opacity", to: spindle, from: 0, to: 1, begin: delay + duration * 0.55, duration: 0.12, timing: CAMediaTimingFunction(name: .linear))
    }
}
