import Foundation
import YTMusicKit

// Developer tool: exercises the parsers against the live API (signed out).
// Usage: swift run ytm-probe [home|explore|search <q>|browse <id> [params]|next <videoId>|suggest <q>|all]

let client = YTMusicClient()

func show(_ page: BrowsePage, label: String) {
    print("=== \(label)")
    if let h = page.header {
        print("HEADER [\(h.kind)] \(h.title) | \(h.subtitle ?? "-") | \(h.secondSubtitle ?? "-") | artists=\(h.artists.map(\.name)) play=\(h.play.map { "\($0.videoId ?? "-")/\($0.playlistId ?? "-")" } ?? "nil") shuffle=\(h.shuffle != nil) radio=\(h.radio != nil) art=\(h.artwork.thumbs.count) subs=\(h.subscribers ?? "-")")
    }
    if !page.chips.isEmpty { print("CHIPS", page.chips.map(\.title)) }
    for s in page.shelves {
        print("  [\(s.style)] \(s.title.isEmpty ? "(untitled)" : s.title) strap=\(s.strapline ?? "-") items=\(s.items.count) more=\(s.more != nil) cont=\(s.continuation != nil)")
        for it in s.items.prefix(3) { print("     - \(describe(it))") }
    }
    print("  continuation:", page.continuation != nil)
}

func describe(_ it: MediaItem) -> String {
    "\(it.kind.rawValue): \(it.title) | \(it.artistLine) | album=\(it.album?.name ?? "-") dur=\(it.duration ?? "-") vid=\(it.videoId ?? "-") browse=\(it.browse?.browseId ?? "-") play=\(it.play.map { "\($0.videoId ?? "")/\($0.playlistId ?? "")" } ?? "-") art=\(it.artwork.url(size: 300)?.absoluteString.prefix(60) ?? "none")"
}

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "all"

do {
    switch cmd {
    case "home":
        var p = try await client.home()
        show(p, label: "HOME")
        var n = 0
        while let c = p.continuation, n < 4 {
            let r = try await client.continuation(c)
            show(BrowsePage(shelves: r.shelves, continuation: r.continuation), label: "HOME cont \(n)")
            p.continuation = r.continuation; n += 1
        }
    case "explore": show(try await client.browse("FEmusic_explore"), label: "EXPLORE")
    case "browse": show(try await client.browse(args[1], params: args.count > 2 ? args[2] : nil), label: args[1])
    case "search":
        let r = try await client.search(args.dropFirst().joined(separator: " "))
        print("TOP:", r.top.map(describe) ?? "nil")
        for t in r.topItems { print("  top+ ", describe(t)) }
        print("CHIPS", r.chips.map { "\($0.title)" })
        show(BrowsePage(shelves: r.shelves), label: "SEARCH")
        if let songs = r.chips.first(where: { $0.title == "Songs" }), case .search(let q, let p)? = songs.endpoint {
            let f = try await client.search(q, params: p)
            show(BrowsePage(shelves: f.shelves), label: "SEARCH songs (cont=\(f.continuation != nil))")
            if let c = f.continuation {
                let more = try await client.searchContinuation(c)
                print("  search continuation items:", more.items.count)
            }
        }
    case "suggest":
        let s = try await client.suggestions(args[1])
        print(s.queries); for i in s.items { print(" ", describe(i)) }
    case "next":
        let q = try await client.next(WatchTarget(videoId: args[1], playlistId: "RDAMVM" + args[1]))
        print("queue items=\(q.items.count) pid=\(q.playlistId ?? "-") cont=\(q.continuation != nil) lyrics=\(q.lyricsBrowseId ?? "-") related=\(q.relatedBrowseId ?? "-")")
        for it in q.items.prefix(5) { print("  ", describe(it)) }
        if let c = q.continuation {
            let more = try await client.nextContinuation(c, playlistId: q.playlistId)
            print("  continuation items=\(more.items.count)")
        }
        if let l = q.lyricsBrowseId, let ly = try await client.lyrics(browseId: l) {
            print("LYRICS:", ly.text.prefix(120), "| source:", ly.source ?? "-")
        }
        if let r = q.relatedBrowseId { show(try await client.browse(r), label: "RELATED") }
    default:
        show(try await client.home(), label: "HOME")
        show(try await client.browse("FEmusic_explore"), label: "EXPLORE")
        show(try await client.browse("FEmusic_moods_and_genres"), label: "MOODS")
        show(try await client.browse("FEmusic_charts"), label: "CHARTS")
        show(try await client.browse("FEmusic_new_releases"), label: "NEW")
        show(try await client.browse("MPREb_L64BnYDQpHZ"), label: "ALBUM")
        show(try await client.browse("UCPC0L1d253x-KuMNwa05TpA"), label: "ARTIST")
        show(try await client.browse("VLPLkpaQgbH2nStd0401Ul7-ffbGc-equxdB"), label: "PLAYLIST")
    }
} catch {
    print("ERROR:", error)
}
