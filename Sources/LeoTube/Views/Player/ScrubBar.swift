import SwiftUI

/// A slim capsule slider that grows and reveals a knob on hover.
struct ScrubBar: View {
    var value: Double              // 0...1
    var height: CGFloat = 4
    var fill: AnyShapeStyle = AnyShapeStyle(Color.primary)
    var onScrub: ((Double) -> Void)? = nil
    var onCommit: (Double) -> Void

    @State private var hovering = false
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let v = min(max(dragValue ?? value, 0), 1)
            let active = hovering || dragValue != nil
            let h = active ? height + 2 : height
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.18)).frame(height: h)
                Capsule()
                    .fill(active ? AnyShapeStyle(Theme.accentGradient) : fill)
                    .frame(width: max(h, geo.size.width * v), height: h)
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: geo.size.width * v - 6.5)
                    .opacity(active ? 1 : 0)
                    .scaleEffect(active ? 1 : 0.4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let nv = min(max(g.location.x / geo.size.width, 0), 1)
                        dragValue = nv
                        onScrub?(nv)
                    }
                    .onEnded { g in
                        let nv = min(max(g.location.x / geo.size.width, 0), 1)
                        onCommit(nv)
                        dragValue = nil
                    }
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        }
        .frame(height: 16)
    }
}

/// Playback position bar with elapsed / remaining labels.
struct PlaybackProgress: View {
    @Environment(AppModel.self) private var app
    var labelFont: Font = .system(size: 11, weight: .medium).monospacedDigit()
    var height: CGFloat = 4
    @State private var scrubTime: Double?

    var body: some View {
        let p = app.player
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let t = scrubTime ?? p.time(at: ctx.date)
            let d = max(p.duration, 0.01)
            HStack(spacing: 10) {
                Text(formatTime(t))
                    .font(labelFont)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                ScrubBar(value: p.isAd ? 0 : t / d, height: height,
                         onScrub: { scrubTime = $0 * d },
                         onCommit: { v in
                             p.seek(to: v * d)
                             scrubTime = nil
                         })
                    .disabled(p.current == nil || p.isAd)
                Text(p.isAd ? "Ad" : formatTime(p.duration))
                    .font(labelFont)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
        }
    }
}

struct VolumeControl: View {
    @Environment(AppModel.self) private var app
    var width: CGFloat = 96
    @State private var lastNonZero: Double = 0.8

    var body: some View {
        let p = app.player
        HStack(spacing: 8) {
            Button {
                if p.volume > 0 { lastNonZero = p.volume; p.volume = 0 } else { p.volume = lastNonZero }
            } label: {
                Image(systemName: symbol(p.volume))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help("Mute")
            ScrubBar(value: p.volume, onScrub: { p.volume = $0 }, onCommit: { p.volume = $0 })
                .frame(width: width)
        }
    }

    private func symbol(_ v: Double) -> String {
        switch v {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// Shuffle / previous / play / next / repeat.
struct TransportControls: View {
    @Environment(AppModel.self) private var app
    var scale: CGFloat = 1
    var showModes = true

    var body: some View {
        let p = app.player
        HStack(spacing: 22 * scale) {
            if showModes {
                toggle("shuffle", active: p.shuffle, help: "Shuffle") { p.toggleShuffle() }
            }
            button("backward.fill", size: 17, help: "Previous") { p.previous() }
            Button {
                p.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    if p.isBuffering && p.isPlaying {
                        ProgressView().controlSize(.small).tint(.black)
                    } else {
                        Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15 * scale, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: p.isPlaying ? 0 : 1.5 * scale)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 38 * scale, height: 38 * scale)
            }
            .buttonStyle(PressScaleStyle())
            .disabled(p.current == nil)
            .help(p.isPlaying ? "Pause" : "Play")
            button("forward.fill", size: 17, help: "Next") { p.next() }
            if showModes {
                toggle(p.repeatMode.symbol, active: p.repeatMode != .off, help: "Repeat") { p.repeatMode = p.repeatMode.next }
            }
        }
        .disabled(p.current == nil)
    }

    private func button(_ name: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size * scale, weight: .semibold))
                .frame(width: 28 * scale, height: 28 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
    }

    private func toggle(_ name: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: name)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                Circle().fill(active ? Theme.accent : .clear).frame(width: 4, height: 4)
            }
            .frame(width: 26 * scale, height: 30 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
