import SwiftUI
import YTMusicKit

/// Loads any browse target and picks the right page layout.
struct BrowseView: View {
    @Environment(AppModel.self) private var app
    let target: BrowseTarget
    @State private var loader = PageLoader()

    var body: some View {
        Group {
            if let page = loader.page {
                switch page.header?.kind {
                case .album?, .playlist?, .podcast?:
                    CollectionView(target: target, loader: loader)
                case .artist?:
                    ArtistView(target: target, loader: loader)
                default:
                    GenericPageView(target: target, loader: loader)
                }
            } else if let err = loader.error {
                ErrorView(message: err) { Task { await loader.load(app, target: target, force: true) } }
            } else {
                LoadingView()
            }
        }
        .task(id: TaskKey(target: target, session: app.sessionID)) {
            await loader.load(app, target: target)
        }
    }
}

/// Pages without a rich header: moods, genres, charts, discography…
struct GenericPageView: View {
    @Environment(AppModel.self) private var app
    let target: BrowseTarget
    let loader: PageLoader

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if let page = loader.page {
                    PageTitle(title: page.header?.title ?? "")
                    if !page.chips.isEmpty {
                        ChipBar(chips: page.chips) { chip in
                            if let e = chip.endpoint { app.handle(e, title: chip.title) }
                        }
                        .padding(.horizontal, Theme.pagePadding)
                    }
                    ForEach(page.shelves) { shelf in
                        ShelfView(shelf: shelf, playsAsList: true)
                        if shelf.continuation != nil {
                            ProgressView().frame(maxWidth: .infinity)
                                .task { await loader.loadMoreItems(app, shelfID: shelf.id) }
                        }
                    }
                    if page.continuation != nil {
                        ProgressView().frame(maxWidth: .infinity).padding()
                            .task { await loader.loadMore(app) }
                    }
                    if page.shelves.isEmpty {
                        ContentUnavailableView("Nothing here yet", systemImage: "music.note.list")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(alignment: .top) { PageGlow(color: Theme.accent) }
    }
}
