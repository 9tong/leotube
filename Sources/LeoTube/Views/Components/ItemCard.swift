import SwiftUI
import YTMusicKit

/// Album / playlist / artist / video card with a hover play button.
struct ItemCard: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var width: CGFloat = Theme.cardWidth
    @State private var hovering = false

    private var isWide: Bool { item.artwork.isWide && (item.kind == .video || item.kind == .episode) }
    private var artWidth: CGFloat { isWide ? width * 1.62 : width }
    private var artHeight: CGFloat { isWide ? artWidth * 9 / 16 : artWidth }
    private var circular: Bool { item.usesCircularArtwork }
    private var canPlay: Bool { item.kind.isPlayable || item.kind.isCollection || item.play != nil }

    var body: some View {
        VStack(alignment: circular ? .center : .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(artwork: item.artwork, size: Int(artWidth * 2), cornerRadius: 10, circle: circular,
                            placeholderSymbol: circular ? "person.fill" : "music.note")
                    .frame(width: artWidth, height: artHeight)
                    .shadow(color: .black.opacity(hovering ? 0.35 : 0.2), radius: hovering ? 14 : 8, y: 6)

                if canPlay, !circular {
                    PlayCircleButton(size: 44) { app.play(item) }
                        .padding(10)
                        .opacity(hovering ? 1 : 0)
                        .offset(y: hovering ? 0 : 8)
                }
                if item.kind == .video || item.kind == .episode, let d = item.duration, !hovering {
                    Text(d)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            VStack(alignment: circular ? .center : .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if item.explicit { ExplicitBadge() }
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(circular ? .center : .leading)
            }
            .frame(width: artWidth, alignment: circular ? .center : .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(duration: 0.28)) { hovering = h } }
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }

    private var subtitle: String {
        if circular, item.subtitle.isEmpty { return item.kindLabel }
        return item.subtitle
    }
}

/// Compact horizontal row used in Quick picks grids and side panels.
struct CompactItemRow: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var width: CGFloat? = 340
    var onPlay: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let isCurrent = item.videoId != nil && app.player.current?.videoId == item.videoId
        HStack(spacing: 12) {
            ZStack {
                ArtworkView(artwork: item.artwork, size: 112, cornerRadius: 6, circle: item.usesCircularArtwork)
                    .frame(width: 48, height: 48)
                if hovering || isCurrent {
                    RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.45)).frame(width: 48, height: 48)
                    if isCurrent && !hovering {
                        EqualizerBars(animating: app.player.isPlaying, color: .white)
                    } else {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if item.explicit { ExplicitBadge() }
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isCurrent ? Theme.accent : .primary)
                        .lineLimit(1)
                }
                ArtistLinksText(artists: item.artists, fallback: item.subtitle)
            }
            Spacer(minLength: 0)
            if hovering, item.videoId != nil {
                LikeButton(item: item, size: 13)
            }
        }
        .padding(6)
        .frame(width: width, alignment: .leading)
        .hoverHighlight(cornerRadius: 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if let onPlay { onPlay() } else { app.open(item) } }
        .contextMenu { ItemMenu(item: item) }
    }
}

/// Colored tile for moods, genres and navigation entries.
struct NavigationTile: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var height: CGFloat = 64
    @State private var hovering = false

    var color: Color { item.color.map(Color.init(argb:)) ?? Theme.accent }

    var body: some View {
        Button {
            if let b = item.browse { app.push(b) }
        } label: {
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: 6)
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [color.opacity(hovering ? 0.42 : 0.28), color.opacity(0.08)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.25)) { hovering = h } }
    }
}
