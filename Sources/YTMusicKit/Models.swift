import Foundation

// MARK: - Artwork

public struct Artwork: Hashable, Sendable, Codable {
    public struct Thumb: Hashable, Sendable, Codable {
        public var url: String
        public var width: Int
        public var height: Int
    }

    public var thumbs: [Thumb]

    public init(thumbs: [Thumb]) { self.thumbs = thumbs }

    public var isEmpty: Bool { thumbs.isEmpty }

    /// Width / height of the largest thumbnail; 1 when unknown.
    public var aspectRatio: Double {
        guard let t = thumbs.last, t.height > 0 else { return 1 }
        return Double(t.width) / Double(t.height)
    }

    public var isWide: Bool { aspectRatio > 1.2 }

    /// Best URL for a target edge length in pixels. Google image CDN URLs are
    /// rewritten to request exactly the size we need.
    public func url(size: Int) -> URL? {
        guard let best = thumbs.last ?? thumbs.first else { return nil }
        var s = best.url
        if s.hasPrefix("//") { s = "https:" + s }
        if s.contains("googleusercontent.com") || s.contains("ggpht.com") {
            if let r = s.range(of: #"=w\d+-h\d+"#, options: .regularExpression) {
                let w: Int, h: Int
                if aspectRatio > 1.2 {
                    w = size * 2; h = Int(Double(size * 2) / aspectRatio)
                } else {
                    w = size; h = size
                }
                s.replaceSubrange(r, with: "=w\(w)-h\(h)")
            } else if let r = s.range(of: #"=s\d+"#, options: .regularExpression) {
                s.replaceSubrange(r, with: "=s\(size)")
            }
        }
        return URL(string: s)
    }

    public var bestURL: URL? { url(size: 1200) }
}

// MARK: - Navigation

public struct BrowseTarget: Hashable, Sendable, Codable {
    public var browseId: String
    public var params: String?
    public var pageType: String?

    public init(browseId: String, params: String? = nil, pageType: String? = nil) {
        self.browseId = browseId
        self.params = params
        self.pageType = pageType
    }
}

public struct WatchTarget: Hashable, Sendable, Codable {
    public var videoId: String?
    public var playlistId: String?
    public var params: String?
    public var index: Int?

    public init(videoId: String? = nil, playlistId: String? = nil, params: String? = nil, index: Int? = nil) {
        self.videoId = videoId
        self.playlistId = playlistId
        self.params = params
        self.index = index
    }
}

public enum Endpoint: Hashable, Sendable, Codable {
    case browse(BrowseTarget)
    case watch(WatchTarget)
    case search(query: String, params: String?)
    case url(String)

    public var browse: BrowseTarget? { if case .browse(let b) = self { return b }; return nil }
    public var watch: WatchTarget? { if case .watch(let w) = self { return w }; return nil }
}

public struct EntityLink: Hashable, Sendable, Codable {
    public var name: String
    public var browseId: String?

    public init(name: String, browseId: String? = nil) {
        self.name = name
        self.browseId = browseId
    }
}

// MARK: - Items

public enum ItemKind: String, Sendable, Codable {
    case song, video, album, single, playlist, artist, profile, podcast, episode, navigation, unknown

    public var isPlayable: Bool { self == .song || self == .video || self == .episode }
    public var isCollection: Bool { self == .album || self == .single || self == .playlist || self == .podcast }
}

public enum LikeStatus: String, Sendable, Codable {
    case like = "LIKE", dislike = "DISLIKE", indifferent = "INDIFFERENT"
}

public struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var kind: ItemKind
    public var title: String
    public var subtitle: String
    public var artists: [EntityLink]
    public var album: EntityLink?
    public var artwork: Artwork
    public var videoId: String?
    public var playlistId: String?
    public var browse: BrowseTarget?
    /// The endpoint used when the item's play button is pressed (for
    /// collections this starts the whole album / playlist).
    public var play: WatchTarget?
    public var duration: String?
    public var index: String?
    public var explicit: Bool
    public var likeStatus: LikeStatus?
    public var setVideoId: String?
    public var color: UInt32?
    public var extra: String?

    public init(id: String, kind: ItemKind, title: String, subtitle: String = "", artists: [EntityLink] = [],
                album: EntityLink? = nil, artwork: Artwork = Artwork(thumbs: []), videoId: String? = nil,
                playlistId: String? = nil, browse: BrowseTarget? = nil, play: WatchTarget? = nil,
                duration: String? = nil, index: String? = nil, explicit: Bool = false,
                likeStatus: LikeStatus? = nil, setVideoId: String? = nil, color: UInt32? = nil, extra: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.subtitle = subtitle
        self.artists = artists; self.album = album; self.artwork = artwork; self.videoId = videoId
        self.playlistId = playlistId; self.browse = browse; self.play = play; self.duration = duration
        self.index = index; self.explicit = explicit; self.likeStatus = likeStatus
        self.setVideoId = setVideoId; self.color = color; self.extra = extra
    }

    public var artistLine: String {
        artists.isEmpty ? subtitle : artists.map(\.name).joined(separator: ", ")
    }

    public var durationSeconds: Double? {
        guard let d = duration else { return nil }
        let parts = d.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Artist page link of the primary artist, if any.
    public var primaryArtistId: String? { artists.first(where: { $0.browseId != nil })?.browseId }
}

// MARK: - Pages

public enum ShelfStyle: String, Sendable, Codable {
    case carousel        // horizontally scrolling cards
    case quickPicks      // horizontally scrolling grid of compact rows
    case list            // vertical track list
    case grid            // wrapping grid of cards
    case navigation      // mood / genre tiles
    case description     // free text
}

public struct Shelf: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var strapline: String?
    public var straplineArtwork: Artwork?
    public var style: ShelfStyle
    public var items: [MediaItem]
    public var more: Endpoint?
    public var text: String?
    public var continuation: String?

    public init(id: String, title: String, strapline: String? = nil, straplineArtwork: Artwork? = nil,
                style: ShelfStyle, items: [MediaItem], more: Endpoint? = nil, text: String? = nil,
                continuation: String? = nil) {
        self.id = id; self.title = title; self.strapline = strapline; self.straplineArtwork = straplineArtwork
        self.style = style; self.items = items; self.more = more; self.text = text; self.continuation = continuation
    }
}

public struct Chip: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public var title: String
    public var endpoint: Endpoint?
    public var selected: Bool
}

public enum HeaderKind: String, Sendable {
    case album, playlist, artist, podcast, generic
}

public struct PageHeader: Hashable, Sendable {
    public var kind: HeaderKind
    public var title: String
    public var subtitle: String?
    public var secondSubtitle: String?
    public var description: String?
    public var artwork: Artwork
    public var artists: [EntityLink]
    public var authorArtwork: Artwork?
    public var play: WatchTarget?
    public var shuffle: WatchTarget?
    public var radio: WatchTarget?
    public var playlistId: String?
    public var channelId: String?
    public var subscribers: String?
    public var subscribed: Bool?
    public var saved: Bool?
    public var isEditable: Bool
    public var monthlyListeners: String?

    public init(kind: HeaderKind, title: String, subtitle: String? = nil, secondSubtitle: String? = nil,
                description: String? = nil, artwork: Artwork = Artwork(thumbs: []), artists: [EntityLink] = [],
                authorArtwork: Artwork? = nil, play: WatchTarget? = nil, shuffle: WatchTarget? = nil,
                radio: WatchTarget? = nil, playlistId: String? = nil, channelId: String? = nil,
                subscribers: String? = nil, subscribed: Bool? = nil, saved: Bool? = nil,
                isEditable: Bool = false, monthlyListeners: String? = nil) {
        self.kind = kind; self.title = title; self.subtitle = subtitle; self.secondSubtitle = secondSubtitle
        self.description = description; self.artwork = artwork; self.artists = artists
        self.authorArtwork = authorArtwork; self.play = play; self.shuffle = shuffle; self.radio = radio
        self.playlistId = playlistId; self.channelId = channelId; self.subscribers = subscribers
        self.subscribed = subscribed; self.saved = saved; self.isEditable = isEditable
        self.monthlyListeners = monthlyListeners
    }
}

public struct BrowsePage: Sendable {
    public var header: PageHeader?
    public var shelves: [Shelf]
    public var chips: [Chip]
    public var continuation: String?

    public init(header: PageHeader? = nil, shelves: [Shelf] = [], chips: [Chip] = [], continuation: String? = nil) {
        self.header = header; self.shelves = shelves; self.chips = chips; self.continuation = continuation
    }

    /// The main track list of an album / playlist page.
    public var tracks: [MediaItem] {
        shelves.first(where: { $0.style == .list })?.items ?? []
    }
}

public struct ContinuationResult: Sendable {
    public var shelves: [Shelf]
    /// Items appended to an existing shelf (track lists / grids).
    public var items: [MediaItem]
    public var continuation: String?
}

public struct SearchResults: Sendable {
    public var top: MediaItem?
    public var topItems: [MediaItem]
    public var shelves: [Shelf]
    public var chips: [Chip]
    public var continuation: String?
}

public struct SearchSuggestions: Sendable {
    public var queries: [String]
    public var items: [MediaItem]

    public init(queries: [String] = [], items: [MediaItem] = []) {
        self.queries = queries
        self.items = items
    }
}

public struct WatchQueue: Sendable {
    public var items: [MediaItem]
    public var playlistId: String?
    public var continuation: String?
    public var lyricsBrowseId: String?
    public var relatedBrowseId: String?
    public var likeStatus: LikeStatus?
}

public struct Lyrics: Sendable, Hashable {
    public var text: String
    public var source: String?
}

public struct AccountInfo: Sendable, Hashable, Codable {
    public var name: String
    public var handle: String?
    public var avatar: Artwork
}
