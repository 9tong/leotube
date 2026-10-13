import Observation
import SwiftUI
import YTMusicKit

/// Loads a browse page and its continuations.
@MainActor
@Observable
final class PageLoader {
    private(set) var page: BrowsePage?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var loadedTarget: BrowseTarget?

    func load(_ app: AppModel, target: BrowseTarget, force: Bool = false) async {
        if !force, loadedTarget == target, page != nil { return }
        if let cached = app.cachedPage(target), !force {
            page = cached
            loadedTarget = target
            return
        }
        isLoading = page == nil || loadedTarget != target
        error = nil
        do {
            let p = try await app.page(target, force: force)
            withAnimation(.easeOut(duration: 0.25)) { page = p }
            loadedTarget = target
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetches the next page of shelves (Home feed etc.).
    func loadMore(_ app: AppModel) async {
        guard let token = page?.continuation, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let r = try? await app.client.continuation(token) else {
            page?.continuation = nil
            return
        }
        let existing = Set(page?.shelves.map(\.id) ?? [])
        let fresh = r.shelves.map { s -> Shelf in
            var s = s
            if existing.contains(s.id) { s.id += "-\(UUID().uuidString.prefix(6))" }
            return s
        }
        page?.shelves += fresh
        page?.continuation = r.continuation
    }

    /// Fetches more items for a shelf with its own continuation (long playlists, library lists).
    func loadMoreItems(_ app: AppModel, shelfID: String) async {
        guard let idx = page?.shelves.firstIndex(where: { $0.id == shelfID }),
              let token = page?.shelves[idx].continuation, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let r = try? await app.client.continuation(token) else {
            page?.shelves[idx].continuation = nil
            return
        }
        let existing = Set(page?.shelves[idx].items.map(\.id) ?? [])
        var items = r.items.isEmpty ? r.shelves.flatMap(\.items) : r.items
        items = items.map { i in
            var i = i
            if existing.contains(i.id) { i.id += "#\(UUID().uuidString.prefix(4))" }
            return i
        }
        if page?.header?.kind == .album, let h = page?.header {
            items = items.map { var t = $0; if t.artwork.isEmpty { t.artwork = h.artwork }; return t }
        }
        page?.shelves[idx].items += items
        page?.shelves[idx].continuation = r.continuation
    }

    func removeItem(_ id: String, shelfID: String) {
        guard let idx = page?.shelves.firstIndex(where: { $0.id == shelfID }) else { return }
        page?.shelves[idx].items.removeAll { $0.id == id }
    }
}
