import Foundation
import Observation
import SwiftUI
import YTMusicKit

enum RepeatMode: String, Codable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

enum LyricsState: Equatable {
    case idle, loading, loaded(Lyrics), unavailable
}

/// The native play queue. Owns ordering, shuffle/repeat, radio continuation
/// and autoplay, and drives `PlayerEngine` one track at a time.
@MainActor
@Observable
final class PlaybackController {
    private(set) var queue: [MediaItem] = []
    private(set) var index: Int = -1
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var isLoadingQueue = false
    private(set) var isAd = false
    private(set) var duration: Double = 0
    private(set) var sourceTitle: String?
    private(set) var lyrics: LyricsState = .idle
    private(set) var relatedBrowseId: String?
    private(set) var errorMessage: String?
    var shuffle = false
    var repeatMode: RepeatMode = .off { didSet { defaults.set(repeatMode.rawValue, forKey: "repeatMode") } }
    var volume: Double = 0.8 {
        didSet {
            engine.setVolume(volume)
            defaults.set(volume, forKey: "volume")
            nowPlaying.update(self)
        }
    }
    var autoplay: Bool = true { didSet { defaults.set(autoplay, forKey: "autoplay") } }

    /// Last reported position, plus the moment it was reported, so the UI can
    /// interpolate smoothly between engine polls.
    private(set) var timeAnchor: (time: Double, date: Date) = (0, .now)
    private(set) var likes: [String: LikeStatus] = [:]

    @ObservationIgnored let engine: PlayerEngine
    @ObservationIgnored private let client: YTMusicClient
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var radioContinuation: String?
    @ObservationIgnored private var radioPlaylistId: String?
    @ObservationIgnored private var originalOrder: [MediaItem]?
    @ObservationIgnored private var lyricsBrowseId: String?
    @ObservationIgnored private var trackInfoTask: Task<Void, Never>?
    @ObservationIgnored private var fetchingMore = false
    @ObservationIgnored private var engineLoadedCurrent = false
    @ObservationIgnored private var errorSkipTask: Task<Void, Never>?
    @ObservationIgnored var wantsLyrics = false { didSet { if wantsLyrics { loadLyricsIfNeeded() } } }
    @ObservationIgnored var onToast: ((String) -> Void)?
    @ObservationIgnored var onSignInRequired: ((String) -> Void)?
    @ObservationIgnored private var consecutiveErrors = 0

    init(engine: PlayerEngine, client: YTMusicClient) {
        self.engine = engine
        self.client = client
        if defaults.object(forKey: "volume") != nil { volume = defaults.double(forKey: "volume") }
        if let r = defaults.string(forKey: "repeatMode"), let m = RepeatMode(rawValue: r) { repeatMode = m }
        if defaults.object(forKey: "autoplay") != nil { autoplay = defaults.bool(forKey: "autoplay") }
        engine.setVolume(volume)
        engine.onState = { [weak self] s in self?.apply(s) }
        engine.onEvent = { [weak self] e in self?.handle(e) }
        nowPlaying.configureCommands(self)
        restoreSession()
    }

    // MARK: - Derived

    var current: MediaItem? { queue.indices.contains(index) ? queue[index] : nil }
    var upNext: [MediaItem] { index + 1 < queue.count ? Array(queue[(index + 1)...]) : [] }
    /// Tracks earlier in the queue that have already played.
    var played: [MediaItem] { index > 0 ? Array(queue[..<min(index, queue.count)]) : [] }
    var hasNext: Bool { index + 1 < queue.count || repeatMode == .all || radioContinuation != nil || autoplay }
    var currentTime: Double { timeAnchor.time }

    func time(at date: Date) -> Double {
        guard isPlaying, !isBuffering else { return timeAnchor.time }
        let t = timeAnchor.time + date.timeIntervalSince(timeAnchor.date)
        return duration > 0 ? min(t, duration) : t
    }

    func likeStatus(for item: MediaItem) -> LikeStatus {
        guard let v = item.videoId else { return .indifferent }
        return likes[v] ?? item.likeStatus ?? .indifferent
    }

    // MARK: - Starting playback

    /// Plays a single song and builds a radio queue around it, like YouTube Music.
    func playRadio(from item: MediaItem) {
        guard let vid = item.videoId else { return }
        setQueue([item], index: 0, source: "Radio · \(item.title)")
        Task {
            guard let q = try? await client.next(WatchTarget(videoId: vid, playlistId: "RDAMVM" + vid, params: "wAEB")) else { return }
            guard current?.videoId == vid else { return }
            let rest = q.items.filter { $0.videoId != vid }
            queue = [mergeDetails(item, with: q.items.first { $0.videoId == vid })] + rest
            radioContinuation = q.continuation
            radioPlaylistId = q.playlistId
            if shuffle { applyShuffle() }
            saveSession()
        }
    }

    func play(items: [MediaItem], startAt: Int = 0, source: String? = nil) {
        let playable = items.filter { $0.videoId != nil }
        guard !playable.isEmpty else { return }
        let start = items.indices.contains(startAt) ? (playable.firstIndex { $0.id == items[startAt].id } ?? 0) : 0
        radioContinuation = nil
        radioPlaylistId = nil
        setQueue(playable, index: start, source: source)
    }

    func play(target: WatchTarget, source: String? = nil, shuffled: Bool = false) {
        isLoadingQueue = true
        Task {
            defer { isLoadingQueue = false }
            do {
                let q = try await client.next(target)
                guard !q.items.isEmpty else { onToast?("Nothing to play here"); return }
                var items = q.items
                var start = q.items.firstIndex { $0.videoId == target.videoId } ?? 0
                if shuffled, target.params == nil {
                    items.shuffle()
                    start = 0
                }
                radioContinuation = q.continuation
                radioPlaylistId = q.playlistId
                setQueue(items, index: start, source: source)
            } catch {
                onToast?(error.localizedDescription)
            }
        }
    }

    func shufflePlay(items: [MediaItem], source: String?) {
        let playable = items.filter { $0.videoId != nil }.shuffled()
        play(items: playable, startAt: 0, source: source)
    }

    private func setQueue(_ items: [MediaItem], index: Int, source: String?) {
        originalOrder = nil
        queue = items
        self.index = index
        sourceTitle = source
        if shuffle {
            applyShuffle()
        }
        startCurrent()
        saveSession()
    }

    private func mergeDetails(_ base: MediaItem, with other: MediaItem?) -> MediaItem {
        guard let o = other else { return base }
        var m = base
        if m.duration == nil { m.duration = o.duration }
        if m.artists.isEmpty { m.artists = o.artists }
        if m.album == nil { m.album = o.album }
        if m.artwork.isEmpty { m.artwork = o.artwork }
        return m
    }

    private func startCurrent() {
        guard let item = current, let vid = item.videoId else { return }
        errorSkipTask?.cancel()
        errorMessage = nil
        isAd = false
        duration = item.durationSeconds ?? 0
        timeAnchor = (0, .now)
        isPlaying = true
        isBuffering = true
        lyrics = .idle
        lyricsBrowseId = nil
        relatedBrowseId = nil
        engineLoadedCurrent = true
        engine.load(videoId: vid, playlistId: item.playlistId)
        nowPlaying.update(self)
        loadTrackInfo(for: item)
        prefetchIfNeeded()
    }

    private func loadTrackInfo(for item: MediaItem) {
        trackInfoTask?.cancel()
        guard let vid = item.videoId else { return }
        trackInfoTask = Task {
            guard let q = try? await client.next(WatchTarget(videoId: vid)), !Task.isCancelled,
                  current?.videoId == vid else { return }
            lyricsBrowseId = q.lyricsBrowseId
            relatedBrowseId = q.relatedBrowseId
            if likes[vid] == nil, let s = q.likeStatus { likes[vid] = s }
            if let detailed = q.items.first(where: { $0.videoId == vid }), queue.indices.contains(index) {
                queue[index] = mergeDetails(queue[index], with: detailed)
                nowPlaying.update(self)
            }
            if wantsLyrics { loadLyricsIfNeeded() }
        }
    }

    func loadLyricsIfNeeded() {
        guard lyrics == .idle, let id = lyricsBrowseId, let vid = current?.videoId else {
            if lyrics == .idle, lyricsBrowseId == nil, trackInfoTask == nil { lyrics = .unavailable }
            return
        }
        lyrics = .loading
        Task {
            let l = try? await client.lyrics(browseId: id)
            guard current?.videoId == vid else { return }
            lyrics = l.map { .loaded($0) } ?? .unavailable
        }
    }

    // MARK: - Transport

    /// Development aid for screenshots: moves the queue position without
    /// starting playback.
    func debugSetIndex(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
    }

    /// Reloads the current track from scratch (after a session change).
    func retryCurrent() {
        guard current != nil else { return }
        errorMessage = nil
        startCurrent()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard current != nil else { return }
        if !engineLoadedCurrent {
            let resumeAt = timeAnchor.time
            startCurrent()
            if resumeAt > 5 {
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    seek(to: resumeAt)
                }
            }
            return
        }
        engine.play()
        isPlaying = true
        timeAnchor = (timeAnchor.time, .now)
        nowPlaying.update(self)
    }

    func pause() {
        timeAnchor = (time(at: .now), .now)
        engine.pause()
        isPlaying = false
        nowPlaying.update(self)
    }

    func next() { advance(auto: false) }

    func previous() {
        if time(at: .now) > 4 || index <= 0 {
            seek(to: 0)
            return
        }
        index -= 1
        startCurrent()
        saveSession()
    }

    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        startCurrent()
        saveSession()
    }

    func seek(to t: Double) {
        let clamped = max(0, duration > 0 ? min(t, duration - 0.5) : t)
        engine.seek(to: clamped)
        timeAnchor = (clamped, .now)
        nowPlaying.update(self)
    }

    func skip(by seconds: Double) { seek(to: time(at: .now) + seconds) }

    func toggleShuffle() {
        shuffle.toggle()
        if shuffle { applyShuffle() } else { restoreOrder() }
        saveSession()
    }

    private func applyShuffle() {
        guard index >= 0, index < queue.count else { return }
        originalOrder = queue
        let head = Array(queue[...index])
        let tail = queue[(index + 1)...].shuffled()
        queue = head + tail
    }

    private func restoreOrder() {
        guard let original = originalOrder, let cur = current else { return }
        queue = original
        index = original.firstIndex { $0.id == cur.id } ?? 0
        originalOrder = nil
    }

    private func advance(auto: Bool) {
        if index + 1 < queue.count {
            index += 1
            startCurrent()
        } else if repeatMode == .all, !queue.isEmpty {
            index = 0
            startCurrent()
        } else {
            Task { await extendQueue(thenAdvance: true) }
            return
        }
        saveSession()
    }

    private func prefetchIfNeeded() {
        guard queue.count - index <= 4, radioContinuation != nil, !fetchingMore else { return }
        Task { await extendQueue(thenAdvance: false) }
    }

    /// Appends more tracks from the radio continuation or, failing that,
    /// starts autoplay from the last track.
    private func extendQueue(thenAdvance: Bool) async {
        guard !fetchingMore else { return }
        fetchingMore = true
        defer { fetchingMore = false }
        var more: [MediaItem] = []
        if let c = radioContinuation, let q = try? await client.nextContinuation(c, playlistId: radioPlaylistId) {
            more = q.items
            radioContinuation = q.continuation
        } else if thenAdvance, autoplay, let last = queue.last, let vid = last.videoId,
                  let q = try? await client.next(WatchTarget(videoId: vid, playlistId: "RDAMVM" + vid, params: "wAEB")) {
            more = q.items
            radioContinuation = q.continuation
            radioPlaylistId = q.playlistId
            if sourceTitle != nil { sourceTitle = "Autoplay · similar to \(last.title)" }
        }
        let existing = Set(queue.compactMap(\.videoId))
        let fresh = more.filter { $0.videoId.map { !existing.contains($0) } ?? false }
        queue += fresh
        if shuffle, originalOrder != nil { originalOrder? += fresh }
        if thenAdvance {
            if index + 1 < queue.count {
                index += 1
                startCurrent()
            } else {
                engine.pause()
                isPlaying = false
                timeAnchor = (duration, .now)
                nowPlaying.update(self)
            }
        }
        saveSession()
    }

    // MARK: - Queue editing

    func playNext(_ items: [MediaItem]) {
        let playable = items.filter { $0.videoId != nil }
        guard !playable.isEmpty else { return }
        if current == nil { play(items: playable); return }
        queue.insert(contentsOf: playable, at: index + 1)
        if var original = originalOrder {
            original.insert(contentsOf: playable, at: min(original.count, index + 1))
            originalOrder = original
        }
        onToast?(playable.count == 1 ? "Playing “\(playable[0].title)” next" : "\(playable.count) songs will play next")
        saveSession()
    }

    func addToQueue(_ items: [MediaItem]) {
        let playable = items.filter { $0.videoId != nil }
        guard !playable.isEmpty else { return }
        if current == nil { play(items: playable); return }
        queue += playable
        originalOrder? += playable
        onToast?(playable.count == 1 ? "Added “\(playable[0].title)” to queue" : "Added \(playable.count) songs to queue")
        saveSession()
    }

    /// Resolves a collection (album / playlist) into tracks for queueing.
    func tracks(for item: MediaItem) async -> [MediaItem] {
        if item.videoId != nil { return [item] }
        guard let pid = item.play?.playlistId ?? item.playlistId,
              let q = try? await client.next(WatchTarget(playlistId: pid)) else { return [] }
        return q.items
    }

    func remove(at offsets: IndexSet) {
        let removingCurrent = offsets.contains(index)
        let ids = offsets.map { queue[$0].id }
        let before = offsets.filter { $0 < index }.count
        queue.remove(atOffsets: offsets)
        originalOrder?.removeAll { ids.contains($0.id) }
        index -= before
        if removingCurrent {
            index = min(max(index, 0), queue.count - 1)
            if queue.isEmpty { clear() } else { startCurrent() }
        }
        saveSession()
    }

    /// Moves items within "up next" (offsets relative to the full queue).
    func move(from source: IndexSet, to destination: Int) {
        let cur = current
        queue.move(fromOffsets: source, toOffset: destination)
        if let cur { index = queue.firstIndex { $0.id == cur.id } ?? index }
        saveSession()
    }

    func clearUpNext() {
        guard index >= 0 else { return }
        queue = Array(queue[...index])
        originalOrder = nil
        radioContinuation = nil
        saveSession()
    }

    func clear() {
        engine.stop()
        queue = []
        index = -1
        isPlaying = false
        timeAnchor = (0, .now)
        duration = 0
        sourceTitle = nil
        nowPlaying.update(self)
        saveSession()
    }

    // MARK: - Likes

    func setLike(_ status: LikeStatus, for item: MediaItem) {
        guard let vid = item.videoId else { return }
        let previous = likes[vid]
        likes[vid] = status
        Task {
            do { try await client.rate(videoId: vid, status) }
            catch {
                likes[vid] = previous
                onToast?("Couldn’t update rating: \(error.localizedDescription)")
            }
        }
    }

    func toggleLike(_ item: MediaItem) {
        setLike(likeStatus(for: item) == .like ? .indifferent : .like, for: item)
    }

    // MARK: - Engine callbacks

    private func apply(_ s: EngineState) {
        isAd = s.isAd
        if s.isAd {
            isBuffering = false
            isPlaying = !s.paused
            return
        }
        if s.videoId != nil, s.videoId != current?.videoId { return }
        if s.duration > 0 { duration = s.duration }
        // While a freshly loaded track hasn't started yet, keep showing the
        // intended "playing" state with a buffering indicator.
        let starting = isBuffering && s.paused && s.time < 0.5 && errorMessage == nil
        if !starting { isPlaying = !s.paused }
        isBuffering = s.buffering || starting
        let drift = abs(time(at: .now) - s.time)
        if drift > 0.35 || !isPlaying || s.paused { timeAnchor = (s.time, .now) }
        if let err = s.error, errorMessage == nil {
            errorMessage = err
            consecutiveErrors += 1
            let lower = err.lowercased()
            if lower.contains("sign in") || lower.contains("bot") {
                // YouTube wants an authenticated session; skipping would just fail again.
                isPlaying = false
                isBuffering = false
                onSignInRequired?(err)
            } else if consecutiveErrors < 3 {
                onToast?("Can’t play “\(current?.title ?? "")”: \(err)")
                errorSkipTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    advance(auto: true)
                }
            } else {
                isPlaying = false
                isBuffering = false
                onToast?("Playback stopped: \(err)")
            }
        } else if s.error == nil, s.time > 1 {
            consecutiveErrors = 0
        }
        nowPlaying.update(self, onlyTime: true)
    }

    private func handle(_ e: PlayerEngine.Event) {
        switch e {
        case .ended:
            if repeatMode == .one {
                seek(to: 0)
                engine.play()
            } else {
                advance(auto: true)
            }
        case .play:
            isPlaying = true
        case .pause:
            break
        }
    }

    // MARK: - Session persistence

    private struct Session: Codable {
        var queue: [MediaItem]
        var index: Int
        var time: Double
        var source: String?
    }

    func saveSession() {
        let window = max(0, index - 50)
        let slice = Array(queue[window..<min(queue.count, window + 250)])
        let s = Session(queue: slice, index: index - window, time: time(at: .now), source: sourceTitle)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: "session") }
    }

    private func restoreSession() {
        guard let data = defaults.data(forKey: "session"),
              let s = try? JSONDecoder().decode(Session.self, from: data),
              s.queue.indices.contains(s.index) else { return }
        queue = s.queue
        index = s.index
        sourceTitle = s.source
        duration = queue[index].durationSeconds ?? 0
        timeAnchor = (s.time, .now)
        engineLoadedCurrent = false
        nowPlaying.update(self)
    }
}
