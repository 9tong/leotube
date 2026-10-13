import SwiftUI
import YTMusicKit

/// Context menu shared by cards, rows and the player.
struct ItemMenu: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var removeFromPlaylist: (() -> Void)?

    var body: some View {
        let playable = item.kind.isPlayable || item.kind.isCollection || item.play != nil
        if playable {
            Button("Play", systemImage: "play.fill") { app.play(item) }
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Task { app.player.playNext(await app.player.tracks(for: item)) }
            }
            Button("Add to Queue", systemImage: "text.append") {
                Task { app.player.addToQueue(await app.player.tracks(for: item)) }
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") { app.startRadio(item) }
            Divider()
            Menu("Add to Playlist", systemImage: "music.note.list") {
                Button("New Playlist…", systemImage: "plus") { app.beginNewPlaylist(with: [item]) }
                if !app.editablePlaylists.isEmpty { Divider() }
                ForEach(app.editablePlaylists) { p in
                    Button(p.title) { app.add([item], toPlaylist: p) }
                }
            }
        }
        if item.videoId != nil {
            let liked = app.player.likeStatus(for: item) == .like
            Button(liked ? "Remove from Liked Music" : "Add to Liked Music", systemImage: liked ? "heart.slash" : "heart") {
                if app.requireSignIn() { app.player.toggleLike(item) }
            }
        }
        if item.kind.isCollection, let pid = item.play?.playlistId ?? item.playlistId {
            Button("Save to Library", systemImage: "plus.circle") { app.setSaved(true, playlistId: pid, title: item.title) }
        }
        Divider()
        if let artist = item.artists.first(where: { $0.browseId != nil }), item.kind != .artist {
            Button("Go to Artist", systemImage: "person.crop.circle") { app.openArtist(artist) }
        }
        if let album = item.album, album.browseId != nil {
            Button("Go to Album", systemImage: "square.stack") { app.openAlbum(album) }
        }
        if let removeFromPlaylist {
            Button("Remove from This Playlist", systemImage: "minus.circle", role: .destructive, action: removeFromPlaylist)
        }
        Divider()
        Button("Copy Link", systemImage: "link") { app.copyLink(item) }
        if let url = item.shareURL {
            Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
        }
    }
}

/// Artist names as inline links inside a single truncating Text.
struct ArtistLinksText: View {
    @Environment(AppModel.self) private var app
    var artists: [EntityLink]
    var fallback: String = ""
    var font: Font = .system(size: 12)

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(.secondary)
            .tint(Color.secondary)
            .lineLimit(1)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "leotube", let id = url.host() {
                    app.openArtist(EntityLink(name: "", browseId: id))
                    return .handled
                }
                return .systemAction
            })
    }

    private var attributed: AttributedString {
        guard !artists.isEmpty else { return AttributedString(fallback) }
        var out = AttributedString()
        for (i, a) in artists.enumerated() {
            if i > 0 { out += AttributedString(", ") }
            var part = AttributedString(a.name)
            if let id = a.browseId { part.link = URL(string: "leotube://\(id)") }
            out += part
        }
        return out
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .bold))
            .frame(width: 14, height: 14)
            .background(RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.35)))
            .foregroundStyle(.primary.opacity(0.8))
    }
}

struct LikeButton: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var size: CGFloat = 14
    var alwaysVisible = true

    var body: some View {
        let liked = app.player.likeStatus(for: item) == .like
        Button {
            if app.requireSignIn() { app.player.toggleLike(item) }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(liked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .symbolEffect(.bounce, value: liked)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(alwaysVisible || liked ? 1 : 0)
        .help(liked ? "Remove from Liked Music" : "Add to Liked Music")
    }
}
