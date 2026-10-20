import SwiftUI
import YTMusicKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var suggestions = SearchSuggestions(queries: [], items: [])

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $app.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            NavigationStack(path: $app.path) {
                detailRoot
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .browse(let target): BrowseView(target: target).id(target)
                        }
                    }
            }
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlayerBar()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow, window.isVisible, window.frame.width > 400, window.alphaValue > 0 else { return }
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
