import SwiftUI
import YTMusicKit

struct SearchView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.submittedQuery.isEmpty {
            BrowseAllView()
        } else {
            SearchResultsView(query: app.submittedQuery).id(app.submittedQuery)
        }
    }
}

// MARK: - Browse all

struct BrowseAllView: View {
    @Environment(AppModel.self) private var app
    @State private var loader = PageLoader()
    private let target = BrowseTarget(browseId: "FEmusic_moods_and_genres")

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                PageTitle(title: "Search", subtitle: "Find songs, albums, artists and podcasts — or browse by mood.")
                if let page = loader.page {
                    ForEach(page.shelves) { shelf in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(shelf.title).font(.system(size: 22, weight: .bold))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
                                ForEach(Array(shelf.items.enumerated()), id: \.element.id) { idx, item in
                                    GenreTile(item: item, index: idx)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.pagePadding)
                    }
                } else if let err = loader.error {
                    ErrorView(message: err) { Task { await loader.load(app, target: target, force: true) } }
                } else {
                    LoadingView()
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(alignment: .top) { PageGlow(color: Color(red: 0.9, green: 0.35, blue: 0.6)) }
        .task(id: app.sessionID) { await loader.load(app, target: target) }
    }
}

struct GenreTile: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var index: Int
    @State private var hovering = false

    private var base: Color { item.color.map(Color.init(argb:)) ?? Theme.accent }

    var body: some View {
        Button {
            if let b = item.browse { app.push(b) }
        } label: {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [base, base.mix(with: .black, by: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 120, height: 120)
                    .offset(x: hovering ? 96 : 110, y: hovering ? 34 : 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(item.title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                    .padding(16)
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(hovering ? 1.025 : 1)
            .shadow(color: base.opacity(hovering ? 0.4 : 0.0), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hovering = h } }
    }
}

// MARK: - Results

struct SearchResultsView: View {
    @Environment(AppModel.self) private var app
    let query: String
    @State private var all: SearchResults?
    @State private var filter: Chip?
    @State private var filtered: SearchResults?
    @State private var error: String?
    @State private var loadingMore = false
    @State private var width: CGFloat = 1000

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Results for “\(query)”")
                        .font(.system(size: 28, weight: .heavy))
                        .lineLimit(1)
                    if let chips = all?.chips, !chips.isEmpty {
                        filterBar(chips)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)

                if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else if filter == nil {
                    if let all { allResults(all) } else { LoadingView() }
                } else {
                    if let filtered { filteredResults(filtered) } else { LoadingView() }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .readWidth($width)
        .background(alignment: .top) { PageGlow(color: Color(red: 0.9, green: 0.35, blue: 0.6)) }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do { all = try await app.client.search(query) }
        catch { self.error = error.localizedDescription }
    }

    private func filterBar(_ chips: [Chip]) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chipButton("All", selected: filter == nil) { filter = nil }
                    ForEach(chips) { chip in
                        chipButton(chip.title, selected: filter?.title == chip.title) { select(chip) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.never)
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: Capsule())
    }

    private func select(_ chip: Chip) {
        filter = chip
        filtered = nil
        guard case .search(let q, let params)? = chip.endpoint else { return }
        Task {
            let r = try? await app.client.search(q, params: params)
            if filter?.title == chip.title { filtered = r }
        }
    }

    // MARK: All

    @ViewBuilder private func allResults(_ r: SearchResults) -> some View {
        let items = r.shelves.flatMap(\.items)
        let songs = Array((r.topItems + items).filter { $0.kind == .song }.uniqued().prefix(5))
        let topLayout = width < 760
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
        topLayout {
            if let top = r.top {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top result").font(.system(size: 22, weight: .bold))
                    TopResultCard(item: top)
                }
                .frame(maxWidth: width < 760 ? .infinity : 420)
            }
            if !songs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Songs").font(.system(size: 22, weight: .bold)).padding(.leading, 12)
                    VStack(spacing: 2) {
                        ForEach(songs) { s in
                            TrackRow(item: s, showAlbum: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.pagePadding - (r.top == nil ? 12 : 0))

        let used = Set(songs.map(\.id) + [r.top?.id].compactMap { $0 })
        ForEach(groups(items.filter { !used.contains($0.id) } + r.topItems.filter { !used.contains($0.id) && $0.kind != .song })) { shelf in
            if shelf.items.allSatisfy({ $0.kind == .song }) {
                ListShelf(shelf: shelf)
            } else {
                CarouselShelf(shelf: shelf)
            }
        }
    }

    private func groups(_ items: [MediaItem]) -> [Shelf] {
        let order: [(String, (MediaItem) -> Bool)] = [
            ("Artists", { $0.kind == .artist }),
            ("Albums", { $0.kind == .album || $0.kind == .single }),
            ("Songs", { $0.kind == .song }),
            ("Videos", { $0.kind == .video }),
            ("Playlists", { $0.kind == .playlist }),
            ("Podcasts", { $0.kind == .podcast }),
            ("Episodes", { $0.kind == .episode }),
            ("Profiles", { $0.kind == .profile }),
        ]
        let unique = items.uniqued()
        return order.compactMap { title, match in
            let list = unique.filter(match)
            return list.isEmpty ? nil : Shelf(id: "search-\(title)", title: title, style: .carousel, items: list)
        }
    }

    // MARK: Filtered

    @ViewBuilder private func filteredResults(_ r: SearchResults) -> some View {
        let items = r.shelves.flatMap(\.items)
        if items.isEmpty {
            ContentUnavailableView.search(text: query).frame(maxWidth: .infinity, minHeight: 300)
        } else if items.allSatisfy({ $0.videoId != nil }) {
            VStack(spacing: 2) {
                ForEach(items) { TrackRow(item: $0) }
            }
            .padding(.horizontal, Theme.pagePadding - 12)
        } else {
            GridShelf(shelf: Shelf(id: "filtered", title: "", style: .grid, items: items))
        }
        if r.continuation != nil {
            ProgressView().frame(maxWidth: .infinity).padding()
                .task(id: items.count) { await loadMoreFiltered() }
        }
    }

    private func loadMoreFiltered() async {
        guard let token = filtered?.continuation, !loadingMore, var current = filtered else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let more = try? await app.client.searchContinuation(token) else {
            filtered?.continuation = nil
            return
        }
        if current.shelves.isEmpty { current.shelves = [Shelf(id: "f", title: "", style: .list, items: [])] }
        let existing = Set(current.shelves[0].items.map(\.id))
        current.shelves[0].items += more.items.filter { !existing.contains($0.id) }
        current.continuation = more.continuation
        filtered = current
    }
}

struct TopResultCard: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                ArtworkView(artwork: item.artwork, size: 300, cornerRadius: 10, circle: item.usesCircularArtwork,
                            placeholderSymbol: item.usesCircularArtwork ? "person.fill" : "music.note")
                    .frame(width: 108, height: 108)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                Text(item.title)
                    .font(.system(size: 30, weight: .black))
                    .tracking(-0.5)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(item.kindLabel)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.primary.opacity(0.12), in: Capsule())
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)

            if item.kind.isPlayable || item.kind.isCollection || item.kind == .artist {
                PlayCircleButton(size: 52) {
                    if item.kind == .artist, let b = item.browse {
                        Task {
                            if let page = try? await app.page(b), let s = page.header?.shuffle ?? page.header?.radio {
                                app.player.play(target: s, source: item.title)
                            }
                        }
                    } else {
                        app.play(item)
                    }
                }
                .padding(20)
                .opacity(hovering ? 1 : 0)
                .offset(y: hovering ? 0 : 8)
            }
        }
        .background(.quaternary.opacity(hovering ? 0.55 : 0.35), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hovering = h } }
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }

    private var detail: String {
        var parts = item.subtitle.components(separatedBy: " • ")
        if parts.first == item.kindLabel { parts.removeFirst() }
        return parts.joined(separator: " • ")
    }
}

extension Array where Element == MediaItem {
    func uniqued() -> [MediaItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
