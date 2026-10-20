import SwiftUI
import YTMusicKit

enum LibraryTab: String, CaseIterable, Identifiable {
    case playlists = "Playlists", songs = "Songs", albums = "Albums", artists = "Artists",
         podcasts = "Podcasts", history = "History"

    var id: String { rawValue }

    var browseId: String {
        switch self {
        case .playlists: return "FEmusic_liked_playlists"
        case .songs: return "FEmusic_liked_videos"
        case .albums: return "FEmusic_liked_albums"
        case .artists: return "FEmusic_library_corpus_track_artists"
        case .podcasts: return "FEmusic_library_non_music_audio_list"
        case .history: return "FEmusic_history"
        }
    }

    var symbol: String {
        switch self {
        case .playlists: return "music.note.list"
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .podcasts: return "mic"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("libraryTab") private var tab: LibraryTab = .playlists
    @State private var loader = PageLoader()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom) {
                    PageTitle(title: "Your Library")
                    Spacer()
                    if app.auth.isSignedIn, tab == .playlists {
                        Button {
                            app.beginNewPlaylist()
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).frame(height: 34)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .padding(.trailing, Theme.pagePadding)
                    }
                }
                if app.auth.isSignedIn {
                    tabBar
                    content
                } else {
                    SignInPrompt(message: "Sign in to see your playlists, liked songs, albums and listening history.")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(alignment: .top) { PageGlow(color: Color(red: 0.2, green: 0.7, blue: 0.6)) }
        .task(id: TaskKey(target: BrowseTarget(browseId: tab.browseId), session: app.sessionID)) {
            guard app.auth.isSignedIn else { return }
            await loader.load(app, target: BrowseTarget(browseId: tab.browseId))
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases) { t in
                    Button {
                        withAnimation(.spring(duration: 0.3)) { tab = t }
                    } label: {
                        Label(t.rawValue, systemImage: t.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(tab == t ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(tab == t ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: Capsule())
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, Theme.pagePadding)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder private var content: some View {
        if loader.isLoading || loader.loadedTarget?.browseId != tab.browseId {
            LoadingView()
        } else if let err = loader.error {
            ErrorView(message: err) { Task { await loader.load(app, target: BrowseTarget(browseId: tab.browseId), force: true) } }
        } else if let page = loader.page {
            if tab == .playlists {
                LikedMusicBanner().padding(.horizontal, Theme.pagePadding)
            }
            if page.shelves.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: tab.symbol,
                                       description: Text("Items you save on YouTube Music will show up here."))
                    .frame(maxWidth: .infinity, minHeight: 280)
            }
            if tab == .songs, let songs = page.shelves.first(where: { $0.style == .list })?.items, !songs.isEmpty {
                HStack(spacing: 12) {
                    PlayCircleButton(size: 50) { app.player.play(items: songs, source: "Library songs") }
                    GlassIconButton(systemName: "shuffle", size: 40, help: "Shuffle") {
                        app.player.shufflePlay(items: songs, source: "Library songs")
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            ForEach(page.shelves) { shelf in
                let collectionsOnly = shelf.items.allSatisfy { $0.videoId == nil }
                if collectionsOnly, shelf.style == .list || shelf.style == .grid {
                    GridShelf(shelf: tab == .playlists ? filteredPlaylists(shelf) : shelf)
                } else {
                    ShelfView(shelf: shelf, playsAsList: tab == .songs)
                }
                if shelf.continuation != nil {
                    ProgressView().frame(maxWidth: .infinity)
                        .task(id: shelf.items.count) { await loader.loadMoreItems(app, shelfID: shelf.id) }
                }
            }
        }
    }

    private func filteredPlaylists(_ shelf: Shelf) -> Shelf {
        var s = shelf
        s.items.removeAll { $0.browse?.browseId == "VLLM" }
        return s
    }
}

private struct LikedMusicBanner: View {
    @Environment(AppModel.self) private var app
    @State private var hovering = false

    var body: some View {
        Button {
            app.selection = .collection(BrowseTarget(browseId: "VLLM"), title: "Liked Music")
        } label: {
            HStack(spacing: 18) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Liked Music").font(.system(size: 22, weight: .heavy))
                    Text("Every song you’ve given a thumbs up").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Theme.accent.opacity(hovering ? 0.32 : 0.22), Theme.accentSecondary.opacity(0.06)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }
}

struct SignInPrompt: View {
    @Environment(AppModel.self) private var app
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.accentGradient)
            Text("Sign in to YouTube Music").font(.system(size: 22, weight: .bold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Sign In") { app.showLogin = true }
                .buttonStyle(AccentCapsuleStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }
}
