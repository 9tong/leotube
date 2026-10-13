import Foundation

/// Converts raw InnerTube (WEB_REMIX) responses into app models.
///
/// The parser is intentionally generic: every renderer that represents a
/// "thing you can click" becomes a `MediaItem`, and every container becomes a
/// `Shelf`. This keeps Home, Explore, artist pages, moods, library pages and
/// search all rendering through the same small set of views.
public enum Parser {

    // MARK: - Primitive helpers

    static func artwork(_ j: JSON) -> Artwork {
        // Accepts any object that contains a `thumbnails` array somewhere.
        let list: [JSON]
        if j["thumbnails"].exists { list = j["thumbnails"].array }
        else { list = j.first("thumbnails").array }
        var thumbs = list.compactMap { t -> Artwork.Thumb? in
            guard let url = t["url"].string else { return nil }
            return .init(url: url, width: t["width"].int ?? 0, height: t["height"].int ?? 0)
        }
        if thumbs.isEmpty, let src = j.first("sources")[0]["url"].string {
            thumbs = [.init(url: src, width: 0, height: 0)]
        }
        thumbs.sort { $0.width < $1.width }
        return Artwork(thumbs: thumbs)
    }

    static func pageType(_ browseEndpoint: JSON) -> String? {
        browseEndpoint.path("browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType").string
    }

    static func browseTarget(_ endpoint: JSON) -> BrowseTarget? {
        let b = endpoint["browseEndpoint"]
        guard let id = b["browseId"].string else { return nil }
        return BrowseTarget(browseId: id, params: b["params"].string, pageType: pageType(b))
    }

    static func watchTarget(_ endpoint: JSON) -> WatchTarget? {
        let w = endpoint["watchEndpoint"].exists ? endpoint["watchEndpoint"] : endpoint["watchPlaylistEndpoint"]
        guard w.exists else { return nil }
        let vid = w["videoId"].string
        let pid = w["playlistId"].string
        guard vid != nil || pid != nil else { return nil }
        return WatchTarget(videoId: vid, playlistId: pid, params: w["params"].string, index: w["index"].int)
    }

    static func endpoint(_ e: JSON) -> Endpoint? {
        if let b = browseTarget(e) { return .browse(b) }
        if let w = watchTarget(e) { return .watch(w) }
        if let q = e.path("searchEndpoint.query").string { return .search(query: q, params: e.path("searchEndpoint.params").string) }
        if let u = e.path("urlEndpoint.url").string { return .url(u) }
        return nil
    }

    static func musicVideoType(_ endpoint: JSON) -> String? {
        endpoint.path("watchEndpoint.watchEndpointMusicSupportedConfigs.watchEndpointMusicConfig.musicVideoType").string
    }

    static func kind(forVideoType t: String?) -> ItemKind {
        switch t {
        case "MUSIC_VIDEO_TYPE_ATV", nil: return .song
        case "MUSIC_VIDEO_TYPE_PODCAST_EPISODE": return .episode
        default: return .video
        }
    }

    static func kind(forPageType t: String?, firstSubtitle: String?) -> ItemKind {
        switch t {
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK":
            let f = firstSubtitle?.lowercased() ?? ""
            return (f == "single" || f == "ep") ? .single : .album
        case "MUSIC_PAGE_TYPE_PLAYLIST": return .playlist
        case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_LIBRARY_ARTIST": return .artist
        case "MUSIC_PAGE_TYPE_USER_CHANNEL": return .profile
        case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE": return .podcast
        case "MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE": return .episode
        default: return .navigation
        }
    }

    /// Splits subtitle runs into artist links and an album link.
    static func links(from runs: [JSON]) -> (artists: [EntityLink], album: EntityLink?) {
        var artists: [EntityLink] = []
        var album: EntityLink?
        for r in runs {
            guard let t = r["text"].string else { continue }
            let be = r["navigationEndpoint"]["browseEndpoint"]
            switch pageType(be) {
            case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL", "MUSIC_PAGE_TYPE_LIBRARY_ARTIST":
                artists.append(EntityLink(name: t, browseId: be["browseId"].string))
            case "MUSIC_PAGE_TYPE_ALBUM":
                album = EntityLink(name: t, browseId: be["browseId"].string)
            default: break
            }
        }
        return (artists, album)
    }

    static func isSeparator(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t == "•" || t == "&" || t == "," || t == "·" || t.isEmpty
    }

    static func hasExplicitBadge(_ j: JSON) -> Bool {
        j.all("iconType", maxDepth: 8).contains { $0.string == "MUSIC_EXPLICIT_BADGE" }
    }

    static func likeStatus(fromMenu menu: JSON) -> LikeStatus? {
        for b in menu.path("menuRenderer.topLevelButtons").array {
            if let s = b.path("likeButtonRenderer.likeStatus").string { return LikeStatus(rawValue: s) }
        }
        return nil
    }

    static func playTarget(fromOverlay overlay: JSON) -> WatchTarget? {
        watchTarget(overlay.path("musicItemThumbnailOverlayRenderer.content.musicPlayButtonRenderer.playNavigationEndpoint"))
    }

    // MARK: - Items

    public static func item(_ wrapper: JSON) -> MediaItem? {
        guard let key = wrapper.firstKey else { return nil }
        let r = wrapper[key]
        switch key {
        case "musicTwoRowItemRenderer": return twoRow(r)
        case "musicResponsiveListItemRenderer": return responsiveListItem(r)
        case "playlistPanelVideoRenderer": return panelVideo(r)
        case "playlistPanelVideoWrapperRenderer": return panelVideo(r.path("primaryRenderer.playlistPanelVideoRenderer"))
        case "musicNavigationButtonRenderer": return navigationButton(r)
        case "musicMultiRowListItemRenderer": return multiRow(r)
        default: return nil
        }
    }

    static func twoRow(_ r: JSON) -> MediaItem? {
        guard let title = r["title"].text else { return nil }
        let nav = r["navigationEndpoint"]
        let subRuns = r["subtitle"].runs
        let subtitle = r["subtitle"].text ?? ""
        let (artists, album) = links(from: subRuns)
        let art = artwork(r["thumbnailRenderer"])
        let play = playTarget(fromOverlay: r["thumbnailOverlay"])
        let explicit = hasExplicitBadge(r["subtitleBadges"])

        if let b = browseTarget(nav) {
            var k = kind(forPageType: b.pageType, firstSubtitle: subRuns.first?["text"].string)
            if k == .navigation, b.browseId.hasPrefix("MPRE") { k = .album }
            if k == .navigation, b.browseId.hasPrefix("VL") { k = .playlist }
            return MediaItem(id: b.browseId, kind: k, title: title, subtitle: subtitle, artists: artists,
                             album: album, artwork: art, playlistId: play?.playlistId, browse: b, play: play,
                             explicit: explicit)
        }
        if let w = watchTarget(nav) {
            let k: ItemKind = w.videoId == nil ? .playlist : kind(forVideoType: musicVideoType(nav))
            return MediaItem(id: w.videoId ?? w.playlistId ?? title, kind: k, title: title, subtitle: subtitle,
                             artists: artists, album: album, artwork: art, videoId: w.videoId,
                             playlistId: w.playlistId, play: w, explicit: explicit)
        }
        return nil
    }

    static func responsiveListItem(_ r: JSON) -> MediaItem? {
        let cols = r["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"]["text"] }
        guard let title = cols.first?.text, !title.isEmpty else { return nil }
        let titleRun = cols.first?.runs.first ?? .null
        let titleNav = titleRun["navigationEndpoint"]
        let nav = r["navigationEndpoint"]

        var allRuns: [JSON] = []
        var subtitleParts: [String] = []
        for c in cols.dropFirst() {
            allRuns += c.runs
            if let t = c.text, !t.isEmpty { subtitleParts.append(t) }
        }
        let (artists, album) = links(from: allRuns)
        let duration = r["fixedColumns"][0]["musicResponsiveListItemFixedColumnRenderer"]["text"].text
            ?? allRuns.compactMap { $0["text"].string }.last { $0.range(of: #"^\d{1,2}(:\d{2}){1,2}$"#, options: .regularExpression) != nil }
        let art = artwork(r["thumbnail"])
        let overlayPlay = playTarget(fromOverlay: r["overlay"])
        let videoId = r.path("playlistItemData.videoId").string ?? watchTarget(titleNav)?.videoId ?? overlayPlay?.videoId
        let setVideoId = r.path("playlistItemData.playlistSetVideoId").string
        let index = r["index"].text
        let explicit = hasExplicitBadge(r["badges"])
        let like = likeStatus(fromMenu: r["menu"])
        let subtitle = subtitleParts.joined(separator: " • ")

        if let b = browseTarget(nav) ?? (videoId == nil ? browseTarget(titleNav) : nil) {
            var k = kind(forPageType: b.pageType, firstSubtitle: allRuns.first?["text"].string)
            if k == .navigation, b.browseId.hasPrefix("MPRE") { k = .album }
            if k == .episode, let v = videoId {
                return MediaItem(id: v, kind: .episode, title: title, subtitle: subtitle, artists: artists,
                                 artwork: art, videoId: v, browse: b, play: overlayPlay, duration: duration)
            }
            return MediaItem(id: b.browseId, kind: k, title: title, subtitle: subtitle, artists: artists,
                             album: album, artwork: art, playlistId: overlayPlay?.playlistId, browse: b,
                             play: overlayPlay, duration: duration, index: index, explicit: explicit)
        }
        guard let vid = videoId else { return nil }
        var vtype = musicVideoType(titleNav)
        if vtype == nil {
            vtype = r.path("overlay.musicItemThumbnailOverlayRenderer.content.musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint.watchEndpointMusicSupportedConfigs.watchEndpointMusicConfig.musicVideoType").string
        }
        var k = kind(forVideoType: vtype)
        if vtype == nil, art.isWide { k = .video }
        return MediaItem(id: vid, kind: k, title: title, subtitle: subtitle, artists: artists, album: album,
                         artwork: art, videoId: vid, playlistId: watchTarget(titleNav)?.playlistId,
                         play: watchTarget(titleNav) ?? overlayPlay ?? WatchTarget(videoId: vid),
                         duration: duration, index: index, explicit: explicit, likeStatus: like,
                         setVideoId: setVideoId)
    }

    static func panelVideo(_ r: JSON) -> MediaItem? {
        guard let vid = r["videoId"].string, let title = r["title"].text else { return nil }
        let byline = r["longBylineText"].exists ? r["longBylineText"] : r["shortBylineText"]
        var (artists, album) = links(from: byline.runs)
        if artists.isEmpty, let first = byline.runs.first?["text"].string { artists = [EntityLink(name: first)] }
        // Byline looks like "Artist • Album • 2019" or "Artist • 20M views • 141K likes".
        let parts = byline.runs.compactMap { $0["text"].string }.filter { !isSeparator($0) }
        let nav = r["navigationEndpoint"]
        if album == nil, parts.count >= 3, kind(forVideoType: musicVideoType(nav)) == .song {
            album = EntityLink(name: parts[parts.count - 2])
        }
        let subtitle = parts.joined(separator: " • ")
        return MediaItem(id: vid, kind: kind(forVideoType: musicVideoType(nav)), title: title,
                         subtitle: subtitle, artists: artists, album: album, artwork: artwork(r["thumbnail"]),
                         videoId: vid, playlistId: watchTarget(nav)?.playlistId, play: watchTarget(nav),
                         duration: r["lengthText"].text, explicit: hasExplicitBadge(r["badges"]),
                         setVideoId: r["playlistSetVideoId"].string)
    }

    static func navigationButton(_ r: JSON) -> MediaItem? {
        guard let title = r["buttonText"].text, let b = browseTarget(r["clickCommand"]) else { return nil }
        let color = r.path("solid.leftStripeColor").int.map { UInt32(truncatingIfNeeded: $0) }
        return MediaItem(id: b.browseId + (b.params ?? ""), kind: .navigation, title: title, browse: b,
                         color: color, extra: r.path("iconStyle.icon.iconType").string)
    }

    static func multiRow(_ r: JSON) -> MediaItem? {
        guard let title = r["title"].text else { return nil }
        let tap = watchTarget(r["onTap"])
        let b = browseTarget(r["title"].runs.first?["navigationEndpoint"] ?? .null)
        let show = r["secondTitle"].text
        let (artists, _) = links(from: r["secondTitle"].runs)
        let sub = [show, r["subtitle"].text].compactMap { $0 }.joined(separator: " • ")
        let id = tap?.videoId ?? b?.browseId ?? title
        return MediaItem(id: id, kind: .episode, title: title, subtitle: sub, artists: artists,
                         artwork: artwork(r["thumbnail"]), videoId: tap?.videoId, browse: b, play: tap,
                         duration: r.path("playbackProgress.musicPlaybackProgressRenderer.durationText").text?
                            .replacingOccurrences(of: " • ", with: ""),
                         extra: r["description"].text)
    }

    static func cardShelfItem(_ r: JSON) -> MediaItem? {
        guard let title = r["title"].text else { return nil }
        let subtitle = r["subtitle"].text ?? ""
        let (artists, album) = links(from: r["subtitle"].runs)
        let art = artwork(r["thumbnail"])
        let nav = r["title"].runs.first?["navigationEndpoint"] ?? r["onTap"]
        let tapNav = r["onTap"].exists ? r["onTap"] : nav
        if let b = browseTarget(tapNav) ?? browseTarget(nav) {
            let k = kind(forPageType: b.pageType, firstSubtitle: r["subtitle"].runs.first?["text"].string)
            return MediaItem(id: b.browseId, kind: k, title: title, subtitle: subtitle, artists: artists,
                             album: album, artwork: art, browse: b)
        }
        if let w = watchTarget(tapNav) ?? watchTarget(nav), let v = w.videoId {
            return MediaItem(id: v, kind: kind(forVideoType: musicVideoType(tapNav)), title: title,
                             subtitle: subtitle, artists: artists, album: album, artwork: art, videoId: v,
                             play: w)
        }
        return nil
    }

    // MARK: - Shelves

    static func continuationToken(_ shelf: JSON) -> String? {
        let c = shelf["continuations"][0]
        if let t = c.path("nextContinuationData.continuation").string { return t }
        if let t = c.path("nextRadioContinuationData.continuation").string { return t }
        let items = shelf["contents"].exists ? shelf["contents"].array : shelf["items"].array
        if let last = items.last, let t = last.path("continuationItemRenderer.continuationEndpoint.continuationCommand.token").string {
            return t
        }
        return nil
    }

    static func items(_ list: [JSON]) -> [MediaItem] {
        var seen: [String: Int] = [:]
        return list.compactMap(item).map { it in
            var it = it
            let n = seen[it.id, default: 0]
            seen[it.id] = n + 1
            if n > 0 { it.id += "#\(n)" }
            return it
        }
    }

    static func style(for list: [JSON], fallback: ShelfStyle) -> ShelfStyle {
        guard let k = list.first?.firstKey else { return fallback }
        switch k {
        case "musicNavigationButtonRenderer": return .navigation
        case "musicResponsiveListItemRenderer": return fallback == .carousel ? .quickPicks : fallback
        default: return fallback
        }
    }

    public static func shelves(_ contents: [JSON]) -> [Shelf] {
        var out: [Shelf] = []
        for (i, s) in contents.enumerated() {
            guard let key = s.firstKey else { continue }
            let r = s[key]
            let sid = "\(i)-\(key)"
            switch key {
            case "musicCarouselShelfRenderer", "musicImmersiveCarouselShelfRenderer":
                let h = r["header"].firstValue
                let list = r["contents"].array
                let its = items(list)
                guard !its.isEmpty else { continue }
                let titleRun = h["title"].runs.first ?? .null
                let more = endpoint(titleRun["navigationEndpoint"])
                    ?? endpoint(h.path("moreContentButton.buttonRenderer.navigationEndpoint"))
                let strapArt = artwork(h["thumbnail"])
                out.append(Shelf(id: sid + (h["title"].text ?? ""), title: h["title"].text ?? "",
                                 strapline: h["strapline"].text, straplineArtwork: strapArt.isEmpty ? nil : strapArt,
                                 style: style(for: list, fallback: .carousel), items: its, more: more))
            case "musicShelfRenderer", "musicPlaylistShelfRenderer":
                let list = r["contents"].array
                let its = items(list)
                let more = endpoint(r["bottomEndpoint"]) ?? endpoint(r["title"].runs.first?["navigationEndpoint"] ?? .null)
                guard !its.isEmpty else { continue }
                out.append(Shelf(id: sid, title: r["title"].text ?? "", style: style(for: list, fallback: .list),
                                 items: its, more: more, continuation: continuationToken(r)))
            case "gridRenderer":
                let list = r["items"].array
                let its = items(list)
                guard !its.isEmpty else { continue }
                out.append(Shelf(id: sid, title: r.path("header.gridHeaderRenderer.title").text ?? "",
                                 style: style(for: list, fallback: .grid), items: its,
                                 continuation: continuationToken(r)))
            case "itemSectionRenderer":
                let inner = r["contents"].array
                let direct = inner.filter { item($0) != nil }
                if !direct.isEmpty {
                    let its = items(direct)
                    // Merge consecutive untitled item sections (new search layout).
                    if let last = out.last, last.title.isEmpty, last.style == .list, last.id.hasSuffix("itemSectionRenderer") {
                        out[out.count - 1].items += its.filter { n in !last.items.contains { $0.id == n.id } }
                    } else {
                        out.append(Shelf(id: sid, title: "", style: .list, items: its))
                    }
                }
                out += shelves(inner.filter { item($0) == nil }).map { var s = $0; s.id = sid + "/" + s.id; return s }
            case "musicDescriptionShelfRenderer":
                if let t = r["description"].text {
                    out.append(Shelf(id: sid, title: r["header"].text ?? "", style: .description, items: [], text: t))
                }
            case "musicCardShelfRenderer":
                var its: [MediaItem] = []
                if let top = cardShelfItem(r) { its.append(top) }
                its += items(r["contents"].array)
                if !its.isEmpty {
                    out.append(Shelf(id: sid, title: r.path("header.musicCardShelfHeaderBasicRenderer.title").text ?? "",
                                     style: .list, items: its))
                }
            default:
                continue
            }
        }
        return out
    }

    static func chips(_ sectionList: JSON) -> [Chip] {
        sectionList.path("header.chipCloudRenderer.chips").array.compactMap { c in
            let r = c["chipCloudChipRenderer"]
            guard let t = r["text"].text else { return nil }
            return Chip(title: t, endpoint: endpoint(r["navigationEndpoint"]), selected: r["isSelected"].bool ?? false)
        }
    }

    // MARK: - Headers

    static func header(_ root: JSON, browseId: String) -> PageHeader? {
        // Album / playlist pages put the header inside the first tab.
        if let h = root.first("musicResponsiveHeaderRenderer", maxDepth: 12).nonNull {
            var ph = responsiveHeader(h, browseId: browseId)
            if root.first("musicEditablePlaylistDetailHeaderRenderer", maxDepth: 8).exists { ph.isEditable = true }
            return ph
        }
        let hdr = root["header"]
        if let h = hdr["musicImmersiveHeaderRenderer"].nonNull ?? hdr["musicVisualHeaderRenderer"].nonNull {
            return artistHeader(h)
        }
        if let h = hdr["musicDetailHeaderRenderer"].nonNull ?? hdr.path("musicEditablePlaylistDetailHeaderRenderer.header.musicDetailHeaderRenderer").nonNull {
            var ph = PageHeader(kind: browseId.hasPrefix("MPRE") ? .album : .playlist, title: h["title"].text ?? "",
                                subtitle: h["subtitle"].text, secondSubtitle: h["secondSubtitle"].text,
                                description: h["description"].text, artwork: artwork(h["thumbnail"]),
                                artists: links(from: h["subtitle"].runs).artists)
            ph.isEditable = hdr["musicEditablePlaylistDetailHeaderRenderer"].exists
            ph.playlistId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : nil
            return ph
        }
        if let h = hdr["musicHeaderRenderer"].nonNull, let t = h["title"].text {
            return PageHeader(kind: .generic, title: t)
        }
        return nil
    }

    static func responsiveHeader(_ h: JSON, browseId: String) -> PageHeader {
        let kind: HeaderKind
        if browseId.hasPrefix("MPRE") { kind = .album }
        else if browseId.hasPrefix("MPSP") { kind = .podcast }
        else { kind = .playlist }

        var play: WatchTarget?, shuffle: WatchTarget?, radio: WatchTarget?, saved: Bool?
        for b in h["buttons"].array {
            if let p = watchTarget(b.path("musicPlayButtonRenderer.playNavigationEndpoint")) { play = p }
            if b["toggleButtonRenderer"].exists { saved = b.path("toggleButtonRenderer.isToggled").bool }
            for m in b.path("menuRenderer.items").array {
                let n = m["menuNavigationItemRenderer"]
                switch n.path("icon.iconType").string {
                case "MUSIC_SHUFFLE": shuffle = watchTarget(n["navigationEndpoint"])
                case "MIX": radio = watchTarget(n["navigationEndpoint"])
                default: break
                }
            }
        }
        var artists = links(from: h["straplineTextOne"].runs).artists
        if artists.isEmpty, let name = h["straplineTextOne"].text { artists = [EntityLink(name: name)] }
        if artists.isEmpty, let fp = h.path("facepile.avatarStackViewModel").nonNull, let name = fp.path("text.content").string {
            artists = [EntityLink(name: name, browseId: fp.first("browseId").string)]
        }
        let authorArt = h["straplineThumbnail"].exists ? artwork(h["straplineThumbnail"]) :
            (h["facepile"].exists ? artwork(h["facepile"]) : nil)
        var pid = play?.playlistId
        if pid == nil, browseId.hasPrefix("VL") { pid = String(browseId.dropFirst(2)) }
        return PageHeader(kind: kind, title: h["title"].text ?? "", subtitle: h["subtitle"].text,
                          secondSubtitle: h["secondSubtitle"].text,
                          description: h.path("description.musicDescriptionShelfRenderer.description").text,
                          artwork: artwork(h["thumbnail"]), artists: artists, authorArtwork: authorArt,
                          play: play, shuffle: shuffle, radio: radio, playlistId: pid, saved: saved)
    }

    static func artistHeader(_ h: JSON) -> PageHeader {
        let sub = h.path("subscriptionButton.subscribeButtonRenderer")
        var art = artwork(h["thumbnail"])
        if art.isEmpty { art = artwork(h["foregroundThumbnail"]) }
        return PageHeader(kind: .artist, title: h["title"].text ?? "",
                          description: h["description"].text, artwork: art,
                          shuffle: watchTarget(h.path("playButton.buttonRenderer.navigationEndpoint")),
                          radio: watchTarget(h.path("startRadioButton.buttonRenderer.navigationEndpoint")),
                          channelId: sub["channelId"].string,
                          subscribers: sub["longSubscriberCountText"].text ?? sub["subscriberCountText"].text,
                          subscribed: sub["subscribed"].bool,
                          monthlyListeners: h["monthlyListenerCount"].text)
    }

    // MARK: - Pages

    public static func browse(_ root: JSON, browseId: String) -> BrowsePage {
        var page = BrowsePage()
        page.header = header(root, browseId: browseId)

        let contents = root["contents"]
        var sectionLists: [JSON] = []
        if let single = contents["singleColumnBrowseResultsRenderer"].nonNull {
            sectionLists.append(single.path("tabs.0.tabRenderer.content.sectionListRenderer"))
        }
        if let two = contents["twoColumnBrowseResultsRenderer"].nonNull {
            sectionLists.append(two.path("secondaryContents.sectionListRenderer"))
            sectionLists.append(two.path("tabs.0.tabRenderer.content.sectionListRenderer"))
        }
        if sectionLists.isEmpty, let sl = contents["sectionListRenderer"].nonNull { sectionLists.append(sl) }

        for sl in sectionLists where sl.exists {
            page.shelves += shelves(sl["contents"].array)
            page.chips += chips(sl)
            if page.continuation == nil { page.continuation = continuationToken(sl) }
        }

        // Album tracks carry no artwork / artist columns: inherit from header.
        if let h = page.header, h.kind == .album, let idx = page.shelves.firstIndex(where: { $0.style == .list }) {
            page.shelves[idx].items = page.shelves[idx].items.map { t in
                var t = t
                if t.artwork.isEmpty { t.artwork = h.artwork }
                if t.artists.isEmpty { t.artists = h.artists }
                if t.album == nil { t.album = EntityLink(name: h.title, browseId: browseId) }
                if t.kind == .video { t.kind = .song }
                return t
            }
        }
        return page
    }

    public static func continuation(_ root: JSON) -> ContinuationResult {
        let cc = root["continuationContents"]
        if let s = cc["sectionListContinuation"].nonNull {
            return ContinuationResult(shelves: shelves(s["contents"].array), items: [], continuation: continuationToken(s))
        }
        for key in ["musicPlaylistShelfContinuation", "musicShelfContinuation", "playlistPanelContinuation"] {
            if let s = cc[key].nonNull {
                return ContinuationResult(shelves: [], items: items(s["contents"].array), continuation: continuationToken(s))
            }
        }
        if let g = cc["gridContinuation"].nonNull {
            return ContinuationResult(shelves: [], items: items(g["items"].array), continuation: continuationToken(g))
        }
        var list: [JSON] = []
        for a in root["onResponseReceivedActions"].array {
            list += a.path("appendContinuationItemsAction.continuationItems").array
        }
        let token = list.last?.path("continuationItemRenderer.continuationEndpoint.continuationCommand.token").string
        return ContinuationResult(shelves: [], items: items(list), continuation: token)
    }

    public static func search(_ root: JSON) -> SearchResults {
        let sl = root.path("contents.tabbedSearchResultsRenderer.tabs.0.tabRenderer.content.sectionListRenderer")
        var top: MediaItem?
        var topItems: [MediaItem] = []
        var rest: [JSON] = []
        for s in sl["contents"].array {
            if let card = s["musicCardShelfRenderer"].nonNull {
                top = cardShelfItem(card)
                topItems = items(card["contents"].array)
            } else {
                rest.append(s)
            }
        }
        let sh = shelves(rest)
        let cont = sl["contents"].array.compactMap { continuationToken($0.firstValue) }.first
        return SearchResults(top: top, topItems: topItems, shelves: sh, chips: chips(sl), continuation: cont)
    }

    public static func suggestions(_ root: JSON) -> SearchSuggestions {
        var queries: [String] = []
        var its: [MediaItem] = []
        for section in root["contents"].array {
            for c in section.path("searchSuggestionsSectionRenderer.contents").array {
                if let q = c.path("searchSuggestionRenderer.navigationEndpoint.searchEndpoint.query").string {
                    queries.append(q)
                } else if let it = item(c) {
                    its.append(it)
                }
            }
        }
        return SearchSuggestions(queries: queries, items: its)
    }

    public static func watchQueue(_ root: JSON) -> WatchQueue {
        let tabs = root.path("contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer.tabs").array
        let panel = tabs.first?.path("tabRenderer.content.musicQueueRenderer.content.playlistPanelRenderer") ?? .null
        var lyrics: String?, related: String?
        for t in tabs {
            let be = t.path("tabRenderer.endpoint.browseEndpoint")
            switch pageType(be) {
            case "MUSIC_PAGE_TYPE_TRACK_LYRICS": lyrics = be["browseId"].string
            case "MUSIC_PAGE_TYPE_TRACK_RELATED": related = be["browseId"].string
            default: break
            }
        }
        let like = root.path("playerOverlays.playerOverlayRenderer.actions").array
            .compactMap { $0.path("likeButtonRenderer.likeStatus").string }.first.flatMap(LikeStatus.init(rawValue:))
        if panel.exists {
            return WatchQueue(items: items(panel["contents"].array), playlistId: panel["playlistId"].string,
                              continuation: continuationToken(panel), lyricsBrowseId: lyrics, relatedBrowseId: related,
                              likeStatus: like)
        }
        let c = continuation(root)
        return WatchQueue(items: c.items, playlistId: nil, continuation: c.continuation, lyricsBrowseId: lyrics,
                          relatedBrowseId: related, likeStatus: like)
    }

    public static func lyrics(_ root: JSON) -> Lyrics? {
        let shelf = root.first("musicDescriptionShelfRenderer")
        guard let text = shelf["description"].text, !text.isEmpty else { return nil }
        return Lyrics(text: text, source: shelf["footer"].text)
    }

    public static func account(_ root: JSON) -> AccountInfo? {
        let h = root.first("activeAccountHeaderRenderer")
        guard let name = h["accountName"].text else { return nil }
        return AccountInfo(name: name, handle: h["channelHandle"].text, avatar: artwork(h["accountPhoto"]))
    }
}

extension JSON {
    var nonNull: JSON? { exists ? self : nil }
}
