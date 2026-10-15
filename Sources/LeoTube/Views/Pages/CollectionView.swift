import SwiftUI
import YTMusicKit

/// Album, playlist and podcast pages.
struct CollectionView: View {
    @Environment(AppModel.self) private var app
    let target: BrowseTarget
    let loader: PageLoader
    @State private var tint: Color = .gray
    @State private var expandedDescription = false
    @State private var saved: Bool?
    @State private var confirmDelete = false
    @State private var width: CGFloat = 1000

    private var narrow: Bool { width < 640 }
    /// The Album column only fits when there is room for it.
    private var showAlbumColumn: Bool { !isAlbum && width >= 720 }

    private var page: BrowsePage { loader.page ?? BrowsePage() }
    private var header: PageHeader { page.header ?? PageHeader(kind: .playlist, title: "") }
    private var trackShelf: Shelf? { page.shelves.first { $0.style == .list } }
    private var tracks: [MediaItem] { trackShelf?.items ?? [] }
    private var otherShelves: [Shelf] { page.shelves.filter { $0.id != trackShelf?.id } }
    private var isAlbum: Bool { header.kind == .album }
    private var isPlayingThis: Bool {
        guard let cur = app.player.current else { return false }
        return tracks.contains { $0.videoId == cur.videoId } && app.player.isPlaying
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                actions
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.vertical, 22)
                trackList
                    .padding(.horizontal, Theme.pagePadding - 12)
                if let shelf = trackShelf, shelf.continuation != nil {
                    ProgressView().frame(maxWidth: .infinity).padding()
                        .task(id: shelf.items.count) { await loader.loadMoreItems(app, shelfID: shelf.id) }
                }
                if let note = footnote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.top, 18)
                }
                VStack(alignment: .leading, spacing: 34) {
                    ForEach(otherShelves) { ShelfView(shelf: $0) }
                }
                .padding(.top, 40)
            }
            .padding(.bottom, 40)
        }
        .readWidth($width)
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 560)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .dominantColor(of: header.artwork, into: $tint)
        .navigationTitle(header.title)
        .confirmationDialog("Delete “\(header.title)”?", isPresented: $confirmDelete) {
            Button("Delete Playlist", role: .destructive) {
                if let pid = header.playlistId { app.deletePlaylist(pid, title: header.title) }
            }
        } message: {
            Text("This permanently deletes the playlist from your YouTube Music library.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        // Side by side on wide windows; artwork above the title when narrow.
        let layout = narrow
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 28))
        let artSide: CGFloat = narrow ? 180 : (width < 820 ? 190 : 228)
        return layout {
            ArtworkView(artwork: header.artwork, size: 600, cornerRadius: 14)
                .frame(width: artSide, height: artSide)
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text(typeLine)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.primary.opacity(0.85))
                Text(header.title)
                    .font(.system(size: titleSize, weight: .black))
                    .tracking(-1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                let metaLayout = narrow
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 8))
                metaLayout {
                    HStack(spacing: 8) {
                        if let art = header.authorArtwork, !art.isEmpty {
                            ArtworkView(artwork: art, size: 64, circle: true).frame(width: 24, height: 24)
                        }
                        authorLinks
                    }
                    if let s = header.secondSubtitle {
                        HStack(spacing: 8) {
                            if !narrow { Text("•").foregroundStyle(.secondary) }
                            Text(s).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .font(.system(size: 13.5, weight: .semibold))
                if let d = header.description, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(expandedDescription ? 12 : 2)
                        .frame(maxWidth: 640, alignment: .leading)
                        .onTapGesture { withAnimation(.smooth) { expandedDescription.toggle() } }
                        .help("Click to expand")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 24)
    }

    @ViewBuilder private var authorLinks: some View {
        if header.artists.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(Array(header.artists.enumerated()), id: \.offset) { i, a in
                    if i > 0 { Text("&").foregroundStyle(.secondary) }
                    Button(a.name) { app.openArtist(a) }
                        .buttonStyle(.plain)
                        .disabled(a.browseId == nil)
                }
            }
        }
    }

    private var titleSize: CGFloat {
        let long = header.title.count > 28
        if narrow { return long ? 26 : 34 }
        if width < 820 { return long ? 32 : 44 }
        return long ? 40 : 56
    }

    private var typeLine: String {
        (header.subtitle ?? (isAlbum ? "Album" : "Playlist")).uppercased()
    }

    private var footnote: String? {
        guard isAlbum, let d = header.description, d.contains("℗") || d.contains("©") else { return nil }
        return nil
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 14) {
            PlayCircleButton(size: 58, isPlaying: isPlayingThis) {
                if isPlayingThis { app.player.pause() } else { playAll(shuffled: false) }
            }
            .keyboardShortcut(.return, modifiers: [])
            GlassIconButton(systemName: "shuffle", size: 44, help: "Shuffle") { playAll(shuffled: true) }
            if let pid = header.playlistId, !header.isEditable {
                let isSaved = saved ?? header.saved ?? false
                GlassIconButton(systemName: isSaved ? "checkmark" : "plus", size: 44,
                                tint: isSaved ? Theme.accent.opacity(0.7) : nil,
                                help: isSaved ? "Remove from Library" : "Save to Library") {
                    saved = !isSaved
                    app.setSaved(!isSaved, playlistId: pid, title: header.title)
                }
            }
            if header.radio != nil {
                GlassIconButton(systemName: "dot.radiowaves.left.and.right", size: 44, help: "Start Radio") {
                    if let r = header.radio { app.player.play(target: r, source: "Radio · \(header.title)") }
                }
            }
            Menu {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { app.player.playNext(tracks) }
                Button("Add to Queue", systemImage: "text.append") { app.player.addToQueue(tracks) }
                Menu("Add to Playlist", systemImage: "music.note.list") {
                    Button("New Playlist…", systemImage: "plus") { app.beginNewPlaylist(with: tracks) }
                    Divider()
                    ForEach(app.editablePlaylists) { p in Button(p.title) { app.add(tracks, toPlaylist: p) } }
                }
                Divider()
                if let url = shareURL {
                    Button("Copy Link", systemImage: "link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        app.showToast("Link copied")
                    }
                    Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
                }
                if header.isEditable {
                    Divider()
                    Button("Delete Playlist…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .glassEffect(.regular.interactive(), in: Circle())
            .fixedSize()
            Spacer()
            if app.player.isLoadingQueue { ProgressView().controlSize(.small) }
        }
    }

    private var shareURL: URL? {
        if let pid = header.playlistId { return URL(string: "https://music.youtube.com/playlist?list=\(pid)") }
        return URL(string: "https://music.youtube.com/browse/\(target.browseId)")
    }

    private func playAll(shuffled: Bool) {
        if tracks.count >= 1, trackShelf?.continuation == nil || !shuffled {
            if shuffled { app.player.shufflePlay(items: tracks, source: header.title) }
            else { app.player.play(items: tracks, startAt: 0, source: header.title) }
        } else if let s = shuffled ? header.shuffle : header.play {
            app.player.play(target: s, source: header.title)
        } else if let p = header.play {
            app.player.play(target: p, source: header.title, shuffled: shuffled)
        }
    }

    // MARK: Tracks

    @ViewBuilder private var trackList: some View {
        if tracks.isEmpty {
            ContentUnavailableView("No tracks", systemImage: "music.note", description: Text("This collection is empty."))
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack(spacing: 2) {
                TrackListHeader(showArtwork: !isAlbum, showAlbum: showAlbumColumn)
                    .padding(.bottom, 6)
                LazyVStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, item in
                        TrackRow(item: item, number: idx + 1, showArtwork: !isAlbum, showAlbum: showAlbumColumn,
                                 onPlay: { app.player.play(items: tracks, startAt: idx, source: header.title) },
                                 onRemove: removeAction(for: item))
                    }
                }
            }
        }
    }

    private func removeAction(for item: MediaItem) -> (() -> Void)? {
        guard header.isEditable, item.setVideoId != nil, let pid = header.playlistId, let shelf = trackShelf else { return nil }
        return {
            Task {
                if await app.remove(item, fromPlaylist: pid, target: target) {
                    withAnimation { loader.removeItem(item.id, shelfID: shelf.id) }
                }
            }
        }
    }
}
