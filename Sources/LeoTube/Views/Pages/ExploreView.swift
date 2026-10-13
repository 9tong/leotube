import SwiftUI
import YTMusicKit

struct ExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var loader = PageLoader()
    private let target = BrowseTarget(browseId: "FEmusic_explore")

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                PageTitle(title: "Explore", subtitle: "New releases, charts and every mood in music.")
                if let page = loader.page {
                    let (tiles, rest) = split(page.shelves)
                    if let tiles {
                        ExploreTiles(items: tiles.items).padding(.horizontal, Theme.pagePadding)
                    }
                    ForEach(rest) { shelf in
                        ShelfView(shelf: shelf, navigationRows: 2)
                    }
                } else if let err = loader.error {
                    ErrorView(message: err) { Task { await loader.load(app, target: target, force: true) } }
                } else {
                    HomeSkeleton()
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(alignment: .top) { PageGlow(color: Color(red: 0.35, green: 0.3, blue: 0.95)) }
        .task(id: app.sessionID) { await loader.load(app, target: target) }
    }

    /// The untitled navigation shelf at the top becomes large tiles.
    private func split(_ shelves: [Shelf]) -> (Shelf?, [Shelf]) {
        guard let first = shelves.first, first.style == .navigation, first.title.isEmpty else { return (nil, shelves) }
        return (first, Array(shelves.dropFirst()))
    }
}

struct ExploreTiles: View {
    @Environment(AppModel.self) private var app
    let items: [MediaItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                ExploreTile(item: item, palette: palettes[idx % palettes.count]) {
                    if let b = item.browse { app.push(b) }
                }
            }
        }
    }

    private var palettes: [[Color]] {
        [
            [Color(red: 1.0, green: 0.25, blue: 0.4), Color(red: 1.0, green: 0.55, blue: 0.3)],
            [Color(red: 0.3, green: 0.45, blue: 1.0), Color(red: 0.55, green: 0.3, blue: 0.95)],
            [Color(red: 0.1, green: 0.75, blue: 0.6), Color(red: 0.2, green: 0.5, blue: 0.95)],
            [Color(red: 0.95, green: 0.6, blue: 0.1), Color(red: 0.95, green: 0.3, blue: 0.45)],
        ]
    }
}

private struct ExploreTile: View {
    let item: MediaItem
    let palette: [Color]
    let action: () -> Void
    @State private var hovering = false

    var symbol: String {
        switch item.extra {
        case "MUSIC_NEW_RELEASE": return "sparkles"
        case "TRENDING_UP", "MUSIC_CHARTS": return "chart.line.uptrend.xyaxis"
        case "STICKER_EMOTICON", "MOOD": return "face.smiling"
        case "BROADCAST", "PODCAST": return "mic.fill"
        default:
            let t = item.title.lowercased()
            if t.contains("chart") { return "chart.line.uptrend.xyaxis" }
            if t.contains("mood") || t.contains("genre") { return "face.smiling" }
            if t.contains("podcast") { return "mic.fill" }
            if t.contains("new") { return "sparkles" }
            return "music.note"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                    .rotationEffect(.degrees(-12))
                    .offset(x: hovering ? 8 : 18, y: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Text(item.title)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(18)
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: palette[0].opacity(hovering ? 0.45 : 0.2), radius: hovering ? 18 : 10, y: 6)
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3)) { hovering = h } }
    }
}

struct PageTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 34, weight: .heavy))
                .tracking(-0.5)
            if let subtitle {
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}

struct PageGlow: View {
    var color: Color

    var body: some View {
        LinearGradient(colors: [color.opacity(0.4), color.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 460)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}
