import SwiftUI
import YTMusicKit

/// Picks what to play from the user's library without leaving Now Playing:
/// playlists, albums and songs, each playlist or album opening into its tracks.
struct LibraryPanel: View {
    @Environment(AppModel.self) private var app
    @State private var tab = Tab.playlists
    @State private var opened: MediaItem?

    private enum Tab: String, CaseIterable, Identifiable {
        case playlists = "Playlists", albums = "Albums", songs = "Songs"
        var id: String { rawValue }
        var browse: BrowseTarget? {
            switch self {
            case .playlists: return nil // the sidebar's list, already loaded
            case .albums: return BrowseTarget(browseId: LibraryTab.albums.browseId)
            case .songs: return BrowseTarget(browseId: LibraryTab.songs.browseId)
            }
        }
    }

    /// Development aid: shows the panel signed out, for layout captures.
    private static let debugPanel = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_NOWPLAYING_PANEL"]

    private static let likedMusic = MediaItem(id: "VLLM", kind: .playlist, title: "Liked Music", subtitle: "Auto playlist",
                                              browse: BrowseTarget(browseId: "VLLM"))

    var body: some View {
        if !app.auth.isSignedIn, Self.debugPanel == nil {
            SignInPrompt(message: "Sign in to play your playlists, albums and songs from here.")
                .padding(16)
        } else {
            ZStack {
                if let item = opened, let target = item.browse {
                    CollectionTracks(item: item, target: target) { withAnimation(.smooth(duration: 0.35)) { opened = nil } }
                        .id(item.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    root.transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .onAppear { if Self.debugPanel == "library-open" { opened = app.libraryPlaylists.first } }
        }
    }

    private var root: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            switch tab {
            case .playlists:
                list {
                    collectionRow(Self.likedMusic)
                    ForEach(app.libraryPlaylists.filter { $0.browse?.browseId != "VLLM" }) { collectionRow($0) }
                }
                .task { if app.libraryPlaylists.isEmpty { await app.refreshLibraryPlaylists() } }
            case .albums:
                LibraryPage(target: tab.browse!, empty: "No saved albums") { page, loader in
                    list {
                        ForEach(page.shelves.flatMap(\.items).filter { $0.browse != nil }) { collectionRow($0) }
                        LoadMore(page: page, loader: loader)
                    }
                }
                .id(tab)
            case .songs:
                LibraryPage(target: tab.browse!, empty: "No saved songs") { page, loader in
                    TrackPicker(page: page, loader: loader, source: "Library songs", play: page.header?.play, shuffle: page.header?.shuffle)
                }
                .id(tab)
            }
        }
    }

    private func list(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            LazyVStack(spacing: 2, content: content)
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
        }
    }

    private func collectionRow(_ item: MediaItem) -> some View {
        CollectionPickRow(item: item, isLikedMusic: item.id == Self.likedMusic.id) {
            withAnimation(.smooth(duration: 0.35)) { opened = item }
        }
    }
}

/// A playlist or album: click to see its tracks, or play it right away.
private struct CollectionPickRow: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var isLikedMusic = false
    var open: () -> Void
    @State private var hovering = false

    private var isCurrent: Bool { app.player.current != nil && app.player.sourceTitle == item.title }

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if isLikedMusic {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    ArtworkView(artwork: item.artwork, size: 96, cornerRadius: 7)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                Button { app.play(item) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentGradient, in: Circle())
                }
                .buttonStyle(PressScaleStyle())
                .help("Play")
                .transition(.opacity)
            } else if isCurrent {
                EqualizerBars(animating: app.player.isPlaying)
            } else {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(7)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .hoverHighlight(cornerRadius: 12)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu { ItemMenu(item: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play") { app.play(item) }
    }
}

/// One playlist or album, opened inside the panel.
private struct CollectionTracks: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    let target: BrowseTarget
    var back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to Library")
                Text(item.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
            LibraryPage(target: target, empty: "This collection is empty") { page, loader in
                TrackPicker(page: page, loader: loader, source: item.title, play: page.header?.play ?? item.play, shuffle: page.header?.shuffle)
            }
        }
    }
}

/// Play, Shuffle and the songs; clicking a song plays from there.
private struct TrackPicker: View {
    @Environment(AppModel.self) private var app
    let page: BrowsePage
    let loader: PageLoader
    let source: String
    var play: WatchTarget?
    var shuffle: WatchTarget?

    private var shelf: Shelf? { page.shelves.first { $0.style == .list } }

    var body: some View {
        let tracks = shelf?.items ?? []
        ScrollView {
            LazyVStack(spacing: 2) {
                HStack(spacing: 10) {
                    capsule("Play", "play.fill") { app.player.play(items: tracks, source: source) }
                    capsule("Shuffle", "shuffle") {
                        // Part of the list is still on the server: let it shuffle all of it.
                        if shelf?.continuation != nil, let shuffle { app.player.play(target: shuffle, source: source) }
                        else { app.player.shufflePlay(items: tracks, source: source) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .disabled(tracks.isEmpty)
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                    Button { app.player.play(items: tracks, startAt: i, source: source) } label: {
                        QueueRow(item: track, isCurrent: track.videoId != nil && track.videoId == app.player.current?.videoId)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(track.videoId == nil)
                    .hoverHighlight(cornerRadius: 10)
                    .contextMenu { ItemMenu(item: track) }
                }
                LoadMore(page: page, loader: loader)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
    }

    private func capsule(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

private struct LoadMore: View {
    @Environment(AppModel.self) private var app
    let page: BrowsePage
    let loader: PageLoader

    var body: some View {
        if let shelf = page.shelves.first(where: { $0.continuation != nil }) {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding()
                .task(id: shelf.items.count) { await loader.loadMoreItems(app, shelfID: shelf.id) }
        }
    }
}

/// Loads a library page and shows its progress, error and empty states.
private struct LibraryPage<Content: View>: View {
    @Environment(AppModel.self) private var app
    let target: BrowseTarget
    let empty: String
    @ViewBuilder var content: (BrowsePage, PageLoader) -> Content
    @State private var loader = PageLoader()

    var body: some View {
        Group {
            if let err = loader.error {
                ErrorView(message: err) { Task { await loader.load(app, target: target, force: true) } }
            } else if let page = loader.page {
                if page.shelves.allSatisfy(\.items.isEmpty) {
                    ContentUnavailableView(empty, systemImage: "music.note")
                } else {
                    content(page, loader)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: TaskKey(target: target, session: app.sessionID)) { await loader.load(app, target: target) }
    }
}
