import SwiftUI
import YTMusicKit

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var loader = PageLoader()
    @State private var chipParams: String?
    @State private var tint: Color = Theme.accent.opacity(0.6)

    private var target: BrowseTarget { BrowseTarget(browseId: "FEmusic_home", params: chipParams) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                header
                if let page = loader.page {
                    if let hero = heroItem(page) {
                        HeroCard(item: hero.item, strapline: hero.shelf).padding(.horizontal, Theme.pagePadding)
                            .dominantColor(of: hero.item.artwork, into: $tint)
                    }
                    ForEach(page.shelves) { shelf in
                        ShelfView(shelf: shelf)
                    }
                    if page.continuation != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .task { await loader.loadMore(app) }
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
        .scrollIndicators(.automatic)
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .task(id: TaskKey(target: target, session: app.sessionID)) {
            await loader.load(app, target: target)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting() + (app.auth.account.map { ", " + ($0.name.split(separator: " ").first.map(String.init) ?? $0.name) } ?? ""))
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-0.5)
                Text(app.auth.isSignedIn ? "Your personal mix of music, picked for you." : "Sign in for recommendations tuned to your taste.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            if let chips = loader.page?.chips, !chips.isEmpty {
                ChipBar(chips: chips, selectedParams: chipParams) { chip in
                    if case .browse(let b)? = chip.endpoint, b.params != chipParams, !chip.selected {
                        chipParams = b.params
                    } else {
                        chipParams = nil
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func heroItem(_ page: BrowsePage) -> (item: MediaItem, shelf: String)? {
        for shelf in page.shelves.prefix(4) where shelf.style == .carousel {
            if let item = shelf.items.first(where: { ($0.kind == .playlist || $0.kind == .album) && !$0.artwork.isEmpty }) {
                return (item, shelf.title)
            }
        }
        return nil
    }
}

struct TaskKey: Hashable {
    var target: BrowseTarget
    var session: UUID
}

/// Mood filter chips on Liquid Glass.
struct ChipBar: View {
    let chips: [Chip]
    var selectedParams: String?
    var onSelect: (Chip) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        let selected = isSelected(chip)
                        Button {
                            withAnimation(.spring(duration: 0.3)) { onSelect(chip) }
                        } label: {
                            Text(chip.title)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.never)
    }

    private func isSelected(_ chip: Chip) -> Bool {
        guard let selectedParams else { return false }
        switch chip.endpoint {
        case .browse(let b)?: return b.params == selectedParams
        case .search(_, let p)?: return p == selectedParams
        default: return false
        }
    }
}

/// Large featured card at the top of Home.
struct HeroCard: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    var strapline: String
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .leading) {
            ArtworkView(artwork: item.artwork, size: 400, cornerRadius: 0)
                .scaleEffect(1.4)
                .blur(radius: 50)
                .overlay(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
                .clipped()

            HStack(spacing: 28) {
                ArtworkView(artwork: item.artwork, size: 480, cornerRadius: 14, circle: item.usesCircularArtwork)
                    .frame(width: 196, height: 196)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    .scaleEffect(hovering ? 1.03 : 1)

                VStack(alignment: .leading, spacing: 10) {
                    Text(strapline.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(item.title)
                        .font(.system(size: 40, weight: .black))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(item.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                    HStack(spacing: 12) {
                        Button {
                            app.play(item)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 22).padding(.vertical, 10)
                                .foregroundStyle(.white)
                                .background(Theme.accentGradient, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            app.open(item)
                        } label: {
                            Text("Open")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.clear.interactive(), in: Capsule())
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .frame(height: 252)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(duration: 0.35)) { hovering = h } }
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

struct HomeSkeleton: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            RoundedRectangle(cornerRadius: 24).frame(height: 252)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 6).frame(width: 220, height: 22)
                    HStack(spacing: 18) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 10).frame(width: Theme.cardWidth, height: Theme.cardWidth)
                                RoundedRectangle(cornerRadius: 4).frame(width: 130, height: 12)
                                RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 10)
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.quaternary.opacity(pulse ? 0.9 : 0.45))
        .padding(.horizontal, Theme.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}
