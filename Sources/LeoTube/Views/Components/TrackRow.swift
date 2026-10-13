import SwiftUI
import YTMusicKit

/// A row in a track list (album, playlist, search results, library).
struct TrackRow: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var number: Int?
    var showArtwork = true
    var showAlbum = true
    var onPlay: (() -> Void)?
    var onRemove: (() -> Void)?
    @State private var hovering = false

    private var isCurrent: Bool { item.videoId != nil && app.player.current?.videoId == item.videoId }
    private var isTrack: Bool { item.videoId != nil }

    var body: some View {
        HStack(spacing: 14) {
            leading.frame(width: 26)
            if showArtwork {
                ArtworkView(artwork: item.artwork, size: 96, cornerRadius: 6, circle: item.usesCircularArtwork,
                            placeholderSymbol: item.usesCircularArtwork ? "person.fill" : "music.note")
                    .frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if item.explicit { ExplicitBadge() }
                    if !isTrack, !item.kindLabel.isEmpty {
                        Text(item.subtitle.isEmpty ? item.kindLabel : item.subtitle)
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        ArtistLinksText(artists: item.artists, fallback: item.subtitle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showAlbum, isTrack {
                Group {
                    if let album = item.album {
                        Button(album.name) { app.openAlbum(album) }
                            .buttonStyle(.plain)
                            .disabled(album.browseId == nil)
                    } else {
                        Text(" ")
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isTrack {
                LikeButton(item: item, size: 13, alwaysVisible: hovering)
                    .frame(width: 20)
            }
            Text(item.duration ?? "")
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            Menu {
                ItemMenu(item: item, removeFromPlaylist: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isCurrent ? 0.08 : (hovering ? 0.06 : 0)))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { play() }
        .onTapGesture(count: 1) { if !isTrack { app.open(item) } }
        .contextMenu { ItemMenu(item: item, removeFromPlaylist: onRemove) }
    }

    @ViewBuilder private var leading: some View {
        if isCurrent && !hovering {
            EqualizerBars(animating: app.player.isPlaying)
        } else if hovering {
            Button {
                if isCurrent { app.player.togglePlayPause() } else { play() }
            } label: {
                Image(systemName: isCurrent && app.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let number {
            Text("\(number)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
        } else if let idx = item.index {
            Text(idx).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
        } else {
            Image(systemName: item.kind == .video ? "play.rectangle" : "music.note")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
    }

    private func play() {
        if let onPlay { onPlay() } else { app.open(item) }
    }
}

struct TrackListHeader: View {
    var showArtwork = true
    var showAlbum = true

    var body: some View {
        HStack(spacing: 14) {
            Text("#").frame(width: 26)
            if showArtwork { Color.clear.frame(width: 42, height: 1) }
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            if showAlbum { Text("Album").frame(maxWidth: .infinity, alignment: .leading) }
            Color.clear.frame(width: 20, height: 1)
            Image(systemName: "clock").frame(width: 46, alignment: .trailing)
            Color.clear.frame(width: 22, height: 1)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}
