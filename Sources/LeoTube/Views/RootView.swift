import SwiftUI
import YTMusicKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var suggestions = SearchSuggestions(queries: [], items: [])
    /// Where the player bar goes. Kept out of this view's own state: the
    /// frames change on every frame of a sidebar or window resize, and only
    /// the bar should update for that, not the whole window.
    @State private var placement = PlayerBarPlacement()

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $app.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            NavigationStack(path: $app.path) {
                detailRoot
                    .safeAreaPadding(.bottom, Theme.playerInset)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .browse(let target):
                            BrowseView(target: target).id(target)
                                .safeAreaPadding(.bottom, Theme.playerInset)
                        }
                    }
            }
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { placement.detailFrame = $0 }
        }
        .inspector(isPresented: $app.showInspector) {
            QueuePanel()
                .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .searchable(text: $app.searchText, placement: .sidebar, prompt: "Songs, albums, artists, podcasts")
        .searchSuggestions {
            if !app.searchText.isEmpty {
                ForEach(suggestions.queries, id: \.self) { q in
                    Label(q, systemImage: "magnifyingglass").searchCompletion(q)
                }
            }
        }
        .onSubmit(of: .search) { app.search(app.searchText) }
        .task(id: app.searchText) {
            let q = app.searchText
            guard !q.isEmpty else { suggestions = .init(queries: [], items: []); return }
            try? await Task.sleep(for: .milliseconds(160))
            if let s = try? await app.client.suggestions(q), q == app.searchText { suggestions = s }
        }
        // The player bar lives at the root: pages pushed onto the navigation
        // stack (album, artist, playlist…) are drawn in their own layer above
        // anything attached inside the stack, which used to hide the bar.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { placement.rootFrame = $0 }
        .overlay(alignment: .topLeading) {
            PlacedPlayerBar(placement: placement)
        }
        .toolbar(removing: .title)
        .toolbar(app.showNowPlaying || app.showWelcome ? .hidden : .automatic, for: .windowToolbar)
        .overlay {
            if app.showNowPlaying {
                NowPlayingView()
                    .ignoresSafeArea()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .overlay(alignment: .top) {
            if let toast = app.toast {
                ToastView(message: toast.message)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .zIndex(20)
            }
        }
        .overlay {
            if app.showWelcome {
                WelcomeView()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(30)
            }
        }
        .sheet(isPresented: $app.showLogin) {
            LoginSheet()
        }
        .sheet(isPresented: $app.showNewPlaylist) {
            NewPlaylistSheet()
        }
        .tint(Theme.accent)
        .preferredColorScheme(app.appearance.colorScheme)
        .frame(minWidth: 600, minHeight: 500)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { app.windowWidth = $0 }
        .background(WindowReader { app.mainWindow = $0 })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow, window === app.mainWindow else { return }
            let visible = window.occlusionState.contains(.visible)
            if app.isWindowVisible != visible { app.isWindowVisible = visible }
        }
    }

    @ViewBuilder private var detailRoot: some View {
        switch app.selection ?? .home {
        case .home: HomeView().id("home")
        case .explore: ExploreView().id("explore")
        case .library: LibraryView().id("library")
        case .search: SearchView().id("search")
        case .collection(let target, _): BrowseView(target: target).id(target)
        }
    }
}

@Observable
final class PlayerBarPlacement {
    /// The content column's frame in window coordinates; the player bar is
    /// drawn at the root and positioned over it.
    var detailFrame: CGRect = .zero
    /// The root container's frame in the same space, so the bar's offset is
    /// relative to the overlay's own origin (which sits below the toolbar).
    var rootFrame: CGRect = .zero
}

/// The player bar, pinned to the bottom of the content column.
private struct PlacedPlayerBar: View {
    @Environment(AppModel.self) private var app
    let placement: PlayerBarPlacement
    @State private var height = Theme.playerInset

    var body: some View {
        let detail = placement.detailFrame, root = placement.rootFrame
        if detail.width > 0, !app.showNowPlaying, !app.showWelcome {
            PlayerBar()
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(width: detail.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .offset(x: detail.minX - root.minX, y: detail.maxY - root.minY - height)
        }
    }
}

struct ToastView: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }
}

/// Reports the NSWindow that hosts this view.
private struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { onWindow(w) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { onWindow(w) }
    }
}
