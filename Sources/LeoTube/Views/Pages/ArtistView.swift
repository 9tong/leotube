import SwiftUI
import YTMusicKit

struct ArtistView: View {
    @Environment(AppModel.self) private var app
    let target: BrowseTarget
    let loader: PageLoader
    @State private var subscribed: Bool?
    @State private var tint: Color = .gray

    private var page: BrowsePage { loader.page ?? BrowsePage() }
    private var header: PageHeader { page.header ?? PageHeader(kind: .artist, title: "") }
    private var topSongs: Shelf? { page.shelves.first { $0.style == .list } }

    @State private var scrollY: CGFloat = 0
    private let bannerHeight: CGFloat = 430

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                bannerText
                    .frame(maxWidth: .infinity, minHeight: bannerHeight - 60, alignment: .bottomLeading)
                VStack(alignment: .leading, spacing: 38) {
                    actions
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.top, 22)
                    if let top = topSongs {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: top.title.isEmpty ? "Popular" : top.title,
                                          onMore: top.more.map { e in { app.handle(e, title: top.title) } })
                                .padding(.horizontal, 12)
                            ForEach(Array(top.items.enumerated()), id: \.element.id) { idx, item in
                                TrackRow(item: item, number: idx + 1, showAlbum: true) {
                                    app.player.play(items: top.items, startAt: idx, source: "\(header.title) · Top songs")
                                }
                            }
                        }
                        .padding(.horizontal, Theme.pagePadding - 12)
                    }
                    ForEach(page.shelves.filter { $0.id != topSongs?.id }) { shelf in
                        if shelf.style == .description {
                            DescriptionShelf(shelf: Shelf(id: shelf.id, title: shelf.title.isEmpty ? "About" : shelf.title,
                                                          style: .description, items: [], text: shelf.text))
                        } else {
                            ShelfView(shelf: shelf)
                        }
                    }
                }
                .padding(.bottom, 40)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            scrollY = y
        }
        .background(alignment: .top) { bannerImage }
        .dominantColor(of: header.artwork, into: $tint)
        .navigationTitle(header.title)
    }

    /// Fixed artist image behind the scrolling content, with parallax and fade.
    private var bannerImage: some View {
        GeometryReader { geo in
            let stretch = max(0, -scrollY)
            ZStack {
                ArtworkView(artwork: header.artwork, size: 1600, cornerRadius: 0, placeholderSymbol: "person.fill")
                    .frame(width: geo.size.width, height: bannerHeight + stretch)
                    .clipped()
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.7), location: 0.78),
                    .init(color: Color(nsColor: .windowBackgroundColor), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: bannerHeight + stretch)
            .offset(y: -max(0, scrollY) * 0.45)
            .opacity(1 - min(1, max(0, scrollY) / (bannerHeight * 0.9)))
        }
        .frame(height: bannerHeight)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var bannerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            if header.subscribers != nil || header.monthlyListeners != nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1))
                    Text("Artist").font(.system(size: 13, weight: .semibold))
                }
            }
            Text(header.title)
                .font(.system(size: 76, weight: .black))
                .tracking(-2)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            Text([header.monthlyListeners, header.subscribers].compactMap { $0 }.joined(separator: " • "))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 4)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            PlayCircleButton(size: 58) {
                if let s = header.shuffle { app.player.play(target: s, source: header.title) }
                else if let top = topSongs { app.player.play(items: top.items, source: header.title) }
            }
            .help("Shuffle play")
            if let r = header.radio {
                Button {
                    app.player.play(target: r, source: "\(header.title) Radio")
                } label: {
                    Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            if let channel = header.channelId {
                let isSub = subscribed ?? header.subscribed ?? false
                if isSub {
                    Button {
                        subscribed = false
                        app.setSubscribed(false, channelId: channel, name: header.title)
                    } label: {
                        Label("Subscribed", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18).frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                } else {
                    Button("Subscribe") {
                        subscribed = true
                        app.setSubscribed(true, channelId: channel, name: header.title)
                    }
                    .buttonStyle(AccentCapsuleStyle())
                }
            }
            Spacer()
        }
    }
}
