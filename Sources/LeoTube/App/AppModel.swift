import AppKit
import Observation
import SwiftUI
import WebKit
import YTMusicKit

enum SidebarItem: Hashable {
    case home, explore, library, search
    case collection(BrowseTarget, title: String)
}

enum Route: Hashable {
    case browse(BrowseTarget)
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case queue = "Up Next", lyrics = "Lyrics", related = "Related"
    var id: String { rawValue }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark, system, light
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
}

@MainActor
@Observable
final class AppModel {
    let auth = AuthManager()
    let client: YTMusicClient
    let engine: PlayerEngine
    let player: PlaybackController

    var selection: SidebarItem? = .home {
        didSet { if oldValue != selection { path = [] } }
    }
    var path: [Route] = []
    var searchText = ""
    var submittedQuery = ""
    var showQueuePopover = false
    var showInspector = false {
        didSet { updateSidebarForSpace() }
    }
    var columnVisibility: NavigationSplitViewVisibility = .all
    @ObservationIgnored var windowWidth: CGFloat = 1480 {
        didSet { updateSidebarForSpace() }
    }
    @ObservationIgnored private var sidebarAutoHidden = false
    @ObservationIgnored private var sidebarDidNotFit = false
    var inspectorTab: InspectorTab = .queue
    var showNowPlaying = false
    var showLogin = false
    var showWelcome = false
    var showNewPlaylist = false
    var pendingPlaylistItems: [MediaItem] = []
    var libraryPlaylists: [MediaItem] = []
    var playbackNeedsSignIn = false
    @ObservationIgnored private var visitorResetAttempted = false
    var toast: Toast?
    /// Bumped whenever account-dependent pages must reload.
    var sessionID = UUID()
    var appearance: AppearanceMode = .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    var contentLanguage: String { didSet { applyLocale() } }
    var contentRegion: String { didSet { applyLocale() } }

    @ObservationIgnored private var pageCache: [BrowseTarget: (page: BrowsePage, date: Date)] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        let lang = d.string(forKey: "contentLanguage") ?? AppModel.systemLanguage
        let region = d.string(forKey: "contentRegion") ?? (Locale.current.region?.identifier ?? "US")
        contentLanguage = lang
        contentRegion = region
        client = YTMusicClient(language: lang, region: region,
                               cookieProvider: { await AppModel.sessionCookies() })
        engine = PlayerEngine(dataStore: AuthManager.sharedDataStore)
        player = PlaybackController(engine: engine, client: client)
        player.onToast = { [weak self] in self?.showToast($0) }
        player.onSignInRequired = { [weak self] reason in self?.handleSignInRequired(reason) }
        if let a = d.string(forKey: "appearance"), let m = AppearanceMode(rawValue: a) { appearance = m }
    }

    @MainActor static func sessionCookies() async -> [HTTPCookie] {
        await AuthManager.sharedDataStore.httpCookieStore.allCookies()
    }

    static var systemLanguage: String {
        let pref = Locale.preferredLanguages.first ?? "en"
        if pref.hasPrefix("zh-Hant") || pref.hasPrefix("zh-TW") || pref.hasPrefix("zh-HK") { return "zh-TW" }
        if pref.hasPrefix("zh") { return "zh-CN" }
        if pref.hasPrefix("pt-BR") { return "pt" }
        return String(pref.prefix { $0 != "-" })
    }

    private func applyLocale() {
        UserDefaults.standard.set(contentLanguage, forKey: "contentLanguage")
        UserDefaults.standard.set(contentRegion, forKey: "contentRegion")
        let lang = contentLanguage, region = contentRegion
        Task {
            await client.setLocale(language: lang, region: region)
            invalidateCaches()
        }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        let signedIn = await auth.refresh()
        engine.warmUp()
        defer { DebugTour.runIfRequested(self) }
        if let vid = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_PLAY"] {
            showWelcome = false
            if ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_MUTE"] != nil { engine.setVolume(0) }
            player.playRadio(from: MediaItem(id: vid, kind: .song, title: "Debug track", videoId: vid))
            if let seek = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_SEEK"].flatMap(Double.init) {
                Task {
                    // Wait for the song itself (not a pre-roll ad) before seeking.
                    repeat { try? await Task.sleep(for: .seconds(1)) } while player.isAd || player.duration < 60
                    try? await Task.sleep(for: .seconds(2))
                    player.seek(to: seek)
                }
            }
            return
        }
        if signedIn {
            await loadAccount()
        } else if !UserDefaults.standard.bool(forKey: "guestMode") {
            showWelcome = true
        }
    }

    func didSignIn() async {
        showLogin = false
        playbackNeedsSignIn = false
        showWelcome = false
        await auth.refresh()
        await client.resetVisitor()
        invalidateCaches()
        engine.webView.reload()
        await loadAccount()
        showToast(auth.account.map { "Signed in as \($0.name)" } ?? "Signed in")
        if player.errorMessage != nil {
            try? await Task.sleep(for: .seconds(2))
            player.retryCurrent()
        }
    }

    func signOut() async {
        await auth.signOut()
        await client.resetVisitor()
        libraryPlaylists = []
        invalidateCaches()
        engine.webView.reload()
        selection = .home
        showToast("Signed out")
    }

    /// YouTube refused playback for the anonymous session. Start a fresh
    /// visitor session once; if that fails too, ask the user to sign in.
    private func handleSignInRequired(_ reason: String) {
        if auth.isSignedIn || visitorResetAttempted {
            playbackNeedsSignIn = true
            showToast(auth.isSignedIn ? "YouTube couldn’t play this: \(reason)" : "Sign in to keep listening — YouTube is asking to verify you")
            return
        }
        visitorResetAttempted = true
        Task {
            await auth.signOut()
            await client.resetVisitor()
            engine.webView.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
            try? await Task.sleep(for: .seconds(3))
            player.retryCurrent()
        }
    }

    func continueAsGuest() {
        UserDefaults.standard.set(true, forKey: "guestMode")
        showWelcome = false
    }

    private func loadAccount() async {
        auth.account = try? await client.accountInfo()
        await refreshLibraryPlaylists()
    }

    func refreshLibraryPlaylists() async {
        guard auth.isSignedIn else { return }
        guard let page = try? await client.browse("FEmusic_liked_playlists") else { return }
        libraryPlaylists = page.shelves.flatMap(\.items).filter {
            $0.browse != nil && ($0.kind == .playlist || $0.kind == .album)
        }
    }

    var editablePlaylists: [MediaItem] {
        libraryPlaylists.filter { p in
            guard let id = p.browse?.browseId else { return false }
            return id != "VLLM" && id != "VLSE" && !id.hasPrefix("VLRD")
        }
    }

    func invalidateCaches() {
        pageCache.removeAll()
        sessionID = UUID()
    }

    // MARK: - Data

    func page(_ target: BrowseTarget, force: Bool = false) async throws -> BrowsePage {
        if !force, let c = pageCache[target], Date().timeIntervalSince(c.date) < 600 { return c.page }
        let page = try await client.browse(target)
        pageCache[target] = (page, .now)
        return page
    }

    func cachedPage(_ target: BrowseTarget) -> BrowsePage? { pageCache[target]?.page }

    // MARK: - Navigation

    func push(_ target: BrowseTarget) {
        if selection == .search, path.isEmpty, submittedQuery.isEmpty { submittedQuery = searchText }
        path.append(.browse(target))
    }

    /// Primary action for an item (click on a card / row).
    func open(_ item: MediaItem) {
        switch item.kind {
        case .song, .video:
            player.playRadio(from: item)
        case .episode:
            if item.videoId != nil { player.playRadio(from: item) } else if let b = item.browse { push(b) }
        default:
            if let b = item.browse { push(b) }
            else if let p = item.play { player.play(target: p, source: item.title) }
        }
    }

    /// Play button on a card: plays songs directly and collections in full.
    func play(_ item: MediaItem) {
        if item.kind.isPlayable, item.videoId != nil {
            player.playRadio(from: item)
        } else if let p = item.play {
            player.play(target: p, source: item.title)
        } else if let b = item.browse {
            Task {
                guard let page = try? await page(b) else { return }
                if let p = page.header?.play { player.play(target: p, source: page.header?.title) }
                else if let s = page.header?.shuffle { player.play(target: s, source: page.header?.title) }
                else { player.play(items: page.tracks, source: page.header?.title) }
            }
        }
    }

    func startRadio(_ item: MediaItem) {
        if let vid = item.videoId {
            player.play(target: WatchTarget(videoId: vid, playlistId: "RDAMVM" + vid, params: "wAEB"), source: "Radio · \(item.title)")
        } else if let pid = item.play?.playlistId ?? item.playlistId {
            player.play(target: WatchTarget(playlistId: "RDAMPL" + pid, params: "wAEB"), source: "Radio · \(item.title)")
        }
    }

    func handle(_ endpoint: Endpoint, title: String? = nil) {
        switch endpoint {
        case .browse(let b): push(b)
        case .watch(let w): player.play(target: w, source: title)
        case .search(let q, _): search(q)
        case .url(let u): if let url = URL(string: u) { NSWorkspace.shared.open(url) }
        }
    }

    func openArtist(_ link: EntityLink) {
        guard let id = link.browseId else { return }
        push(BrowseTarget(browseId: id, pageType: "MUSIC_PAGE_TYPE_ARTIST"))
    }

    func openAlbum(_ link: EntityLink) {
        guard let id = link.browseId else { return }
        push(BrowseTarget(browseId: id, pageType: "MUSIC_PAGE_TYPE_ALBUM"))
    }

    func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchText = q
        submittedQuery = q
        selection = .search
        path = []
    }

    // MARK: - Library actions

    func requireSignIn() -> Bool {
        if auth.isSignedIn { return true }
        showLogin = true
        return false
    }

    func setSaved(_ saved: Bool, playlistId: String, title: String) {
        guard requireSignIn() else { return }
        Task {
            do {
                try await client.setSaved(playlistId: playlistId, saved)
                showToast(saved ? "Added “\(title)” to your library" : "Removed “\(title)” from your library")
                await refreshLibraryPlaylists()
            } catch { showToast(error.localizedDescription) }
        }
    }

    func setSubscribed(_ subscribed: Bool, channelId: String, name: String) {
        guard requireSignIn() else { return }
        Task {
            do {
                try await client.setSubscribed(channelId: channelId, subscribed)
                showToast(subscribed ? "Subscribed to \(name)" : "Unsubscribed from \(name)")
            } catch { showToast(error.localizedDescription) }
        }
    }

    func add(_ items: [MediaItem], toPlaylist playlist: MediaItem) {
        guard requireSignIn(), let bid = playlist.browse?.browseId else { return }
        let pid = bid.hasPrefix("VL") ? String(bid.dropFirst(2)) : bid
        Task {
            var tracks: [MediaItem] = []
            for i in items { tracks += await player.tracks(for: i) }
            let ids = tracks.compactMap(\.videoId)
            guard !ids.isEmpty else { return }
            do {
                try await client.addToPlaylist(pid, videoIds: ids)
                pageCache[BrowseTarget(browseId: bid)] = nil
                showToast("Added to \(playlist.title)")
            } catch { showToast(error.localizedDescription) }
        }
    }

    func beginNewPlaylist(with items: [MediaItem] = []) {
        guard requireSignIn() else { return }
        pendingPlaylistItems = items
        showNewPlaylist = true
    }

    func createPlaylist(title: String, description: String, privacy: String) {
        let items = pendingPlaylistItems
        pendingPlaylistItems = []
        Task {
            var ids: [String] = []
            for i in items { ids += await player.tracks(for: i).compactMap(\.videoId) }
            do {
                let pid = try await client.createPlaylist(title: title, description: description, privacy: privacy, videoIds: ids)
                showToast("Created “\(title)”")
                await refreshLibraryPlaylists()
                if let pid { selection = .collection(BrowseTarget(browseId: "VL" + pid), title: title) }
            } catch { showToast(error.localizedDescription) }
        }
    }

    func deletePlaylist(_ playlistId: String, title: String) {
        Task {
            do {
                try await client.deletePlaylist(playlistId)
                showToast("Deleted “\(title)”")
                await refreshLibraryPlaylists()
                selection = .library
            } catch { showToast(error.localizedDescription) }
        }
    }

    func remove(_ item: MediaItem, fromPlaylist playlistId: String, target: BrowseTarget) async -> Bool {
        guard let vid = item.videoId, let set = item.setVideoId else { return false }
        do {
            try await client.removeFromPlaylist(playlistId, videoId: vid, setVideoId: set)
            pageCache[target] = nil
            showToast("Removed “\(item.title)”")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    // MARK: - UI helpers

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.35)) { toast = Toast(message: message) }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }

    /// Hides the sidebar while there isn't room for it: narrow windows (e.g.
    /// Split View) or the side panel open on a window under ~1500pt. Acts
    /// only when crossing the threshold, so a sidebar the user re-opens stays.
    private func updateSidebarForSpace() {
        let doesNotFit = windowWidth < 820 || (showInspector && windowWidth < 1500)
        guard doesNotFit != sidebarDidNotFit else { return }
        sidebarDidNotFit = doesNotFit
        if doesNotFit, columnVisibility != .detailOnly {
            sidebarAutoHidden = true
            withAnimation(.spring(duration: 0.35)) { columnVisibility = .detailOnly }
        } else if !doesNotFit, sidebarAutoHidden {
            sidebarAutoHidden = false
            withAnimation(.spring(duration: 0.35)) { columnVisibility = .all }
        }
    }

    func toggleInspector(_ tab: InspectorTab) {
        if showInspector, inspectorTab == tab {
            showInspector = false
        } else {
            inspectorTab = tab
            showInspector = true
        }
    }

    func copyLink(_ item: MediaItem) {
        guard let url = item.shareURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast("Link copied")
    }
}
