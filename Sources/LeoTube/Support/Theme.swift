import SwiftUI
import YTMusicKit

enum Theme {
    static let accent = Color(red: 1.0, green: 0.16, blue: 0.32)
    static let accentSecondary = Color(red: 1.0, green: 0.42, blue: 0.27)
    static let accentGradient = LinearGradient(colors: [accent, accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let pagePadding: CGFloat = 32
    static let playerBarHeight: CGFloat = 76
    static let cardWidth: CGFloat = 176
}

extension Color {
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF) / 255,
                  green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255,
                  opacity: 1)
    }
}

func formatTime(_ t: Double) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let s = Int(t.rounded(.down))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

func greeting() -> String {
    switch Calendar.current.component(.hour, from: Date()) {
    case 5..<12: return "Good morning"
    case 12..<18: return "Good afternoon"
    default: return "Good evening"
    }
}

extension MediaItem {
    var shareURL: URL? {
        if let v = videoId { return URL(string: "https://music.youtube.com/watch?v=\(v)") }
        if let b = browse?.browseId {
            if b.hasPrefix("VL") { return URL(string: "https://music.youtube.com/playlist?list=\(b.dropFirst(2))") }
            if b.hasPrefix("UC") { return URL(string: "https://music.youtube.com/channel/\(b)") }
            return URL(string: "https://music.youtube.com/browse/\(b)")
        }
        if let p = playlistId { return URL(string: "https://music.youtube.com/playlist?list=\(p)") }
        return nil
    }

    var kindLabel: String {
        switch kind {
        case .song: return "Song"
        case .video: return "Video"
        case .album: return "Album"
        case .single: return "Single"
        case .playlist: return "Playlist"
        case .artist: return "Artist"
        case .profile: return "Profile"
        case .podcast: return "Podcast"
        case .episode: return "Episode"
        default: return ""
        }
    }

    var usesCircularArtwork: Bool { kind == .artist || kind == .profile }
}

// MARK: - Reusable styles

/// Adds a gentle highlight on hover, Spotify-style.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 10
    var opacity: Double = 0.07
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? opacity : 0))
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 10, opacity: Double = 0.07) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, opacity: opacity))
    }
}

/// Circular icon button rendered on Liquid Glass.
struct GlassIconButton: View {
    var systemName: String
    var size: CGFloat = 36
    var iconScale: CGFloat = 0.42
    var tint: Color? = nil
    var help: String = ""
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * iconScale, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { .regular.tint($0).interactive() } ?? .regular.interactive(), in: Circle())
        .help(help)
    }
}

/// Solid accent capsule for primary calls to action.
struct AccentCapsuleStyle: ButtonStyle {
    var height: CGFloat = 40
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: height)
            .background(Theme.accentGradient, in: Capsule())
            .shadow(color: Theme.accent.opacity(configuration.isPressed ? 0.2 : 0.4), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The big accent play button used on headers and cards.
struct PlayCircleButton: View {
    var size: CGFloat = 56
    var isPlaying = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.accentGradient)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : size * 0.03)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
            .shadow(color: Theme.accent.opacity(0.45), radius: hovering ? 14 : 8, y: 4)
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.25)) { hovering = h } }
    }
}

/// Animated "now playing" equalizer bars.
struct EqualizerBars: View {
    var animating: Bool
    var color: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = t * (5.5 + Double(i) * 1.7) + Double(i) * 1.3
                    let h = animating ? 0.3 + 0.7 * abs(sin(phase)) : 0.3
                    Capsule().fill(color).frame(width: 3, height: 14 * h)
                }
            }
            .frame(width: 14, height: 14, alignment: .bottom)
        }
    }
}

struct SectionHeader: View {
    var title: String
    var strapline: String?
    var artwork: Artwork?
    var moreTitle = "Show all"
    var onMore: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if let artwork {
                ArtworkView(artwork: artwork, size: 96, circle: true).frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let strapline, !strapline.isEmpty {
                    Text(strapline.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
            }
            Spacer()
            if let onMore {
                Button(moreTitle, action: onMore)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .hoverHighlight(cornerRadius: 6)
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Loading…").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

struct ErrorView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load this page", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry).buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}
