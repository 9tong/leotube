import SwiftUI
import YTMusicKit

/// Renders any `Shelf` according to its style.
struct ShelfView: View {
    @Environment(AppModel.self) private var app
    let shelf: Shelf
    /// Track lists inside a page context play the whole list on double-click.
    var playsAsList = false
    var navigationRows: Int? = nil

    var body: some View {
        switch shelf.style {
        case .carousel: CarouselShelf(shelf: shelf)
        case .quickPicks: QuickPicksShelf(shelf: shelf)
        case .list: ListShelf(shelf: shelf, playsAsList: playsAsList)
        case .grid: GridShelf(shelf: shelf)
        case .navigation: NavigationShelf(shelf: shelf, maxRows: navigationRows)
        case .description: DescriptionShelf(shelf: shelf)
        }
    }
}

private struct ShelfHeader: View {
    @Environment(AppModel.self) private var app
    let shelf: Shelf

    var body: some View {
        if !shelf.title.isEmpty {
            SectionHeader(title: shelf.title, strapline: shelf.strapline, artwork: shelf.straplineArtwork,
                          onMore: shelf.more.map { e in { app.handle(e, title: shelf.title) } })
        }
    }
}

// MARK: - Carousel

struct CarouselShelf: View {
    let shelf: Shelf
    @State private var position = ScrollPosition(idType: String.self)
    @State private var visible: [String] = []
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                ShelfHeader(shelf: shelf)
                if shelf.items.count > 3 {
                    HStack(spacing: 8) {
                        GlassIconButton(systemName: "chevron.left", size: 30, help: "Scroll back") { page(-1) }
                            .disabled(atStart)
                            .opacity(atStart ? 0.35 : 1)
                        GlassIconButton(systemName: "chevron.right", size: 30, help: "Scroll forward") { page(1) }
                            .disabled(atEnd)
                            .opacity(atEnd ? 0.35 : 1)
                    }
                    .opacity(hovering ? 1 : 0.0001)
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 4) {
                    ForEach(shelf.items) { item in
                        ItemCard(item: item)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Theme.pagePadding - 10)
            }
            .scrollIndicators(.never)
            .scrollPosition($position, anchor: .leading)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.6) { visible = $0 }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }

    private var atStart: Bool { visible.contains(shelf.items.first?.id ?? "") }
    private var atEnd: Bool { visible.contains(shelf.items.last?.id ?? "") }

    private func page(_ dir: Int) {
        let ids = shelf.items.map(\.id)
        let visibleIdx = visible.compactMap { ids.firstIndex(of: $0) }.sorted()
        guard let first = visibleIdx.first, let last = visibleIdx.last else { return }
        let stride = max(1, last - first + 1)
        let target = dir > 0 ? min(ids.count - 1, last + 1) : max(0, first - stride)
        withAnimation(.smooth(duration: 0.45)) { position.scrollTo(id: ids[target], anchor: .leading) }
    }
}

// MARK: - Quick picks

struct QuickPicksShelf: View {
    @Environment(AppModel.self) private var app
    let shelf: Shelf

    var rows: Int { shelf.items.count >= 8 ? 4 : max(1, min(4, shelf.items.count)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(shelf: shelf).padding(.horizontal, Theme.pagePadding)
            ScrollView(.horizontal) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60), spacing: 4), count: rows), spacing: 12) {
                    ForEach(Array(shelf.items.enumerated()), id: \.element.id) { idx, item in
                        CompactItemRow(item: item, width: 340) {
                            if item.videoId != nil {
                                let songs = shelf.items.filter { $0.videoId != nil }
                                if songs.count == shelf.items.count {
                                    app.player.play(items: songs, startAt: idx, source: shelf.title)
                                } else {
                                    app.open(item)
                                }
                            } else {
                                app.open(item)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Theme.pagePadding - 6)
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

// MARK: - List

struct ListShelf: View {
    @Environment(AppModel.self) private var app
    let shelf: Shelf
    var playsAsList = false
    var limit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(shelf: shelf)
            let items = limit.map { Array(shelf.items.prefix($0)) } ?? shelf.items
            VStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    TrackRow(item: item, number: playsAsList ? idx + 1 : nil, showAlbum: true) {
                        if playsAsList, item.videoId != nil {
                            app.player.play(items: shelf.items, startAt: idx, source: shelf.title.isEmpty ? nil : shelf.title)
                        } else {
                            app.open(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}

// MARK: - Grid

struct GridShelf: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(shelf: shelf)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.cardWidth + 20), spacing: 4, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(shelf.items) { ItemCard(item: $0) }
            }
            .padding(.horizontal, -10)
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}

// MARK: - Navigation tiles

struct NavigationShelf: View {
    let shelf: Shelf
    var maxRows: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(shelf: shelf)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(shelf.items.prefix(maxRows.map { $0 * 6 } ?? shelf.items.count)) { NavigationTile(item: $0) }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}

// MARK: - Description

struct DescriptionShelf: View {
    let shelf: Shelf
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !shelf.title.isEmpty {
                Text(shelf.title).font(.system(size: 22, weight: .bold))
            }
            Text(shelf.text ?? "")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(expanded ? nil : 4)
                .textSelection(.enabled)
            Button(expanded ? "Show less" : "Read more") { withAnimation(.smooth) { expanded.toggle() } }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(22)
        .frame(maxWidth: 820, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, Theme.pagePadding)
    }
}
