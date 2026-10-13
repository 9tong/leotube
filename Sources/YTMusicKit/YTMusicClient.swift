import CryptoKit
import Foundation

public enum YTMusicError: LocalizedError {
    case http(Int, String?)
    case notSignedIn
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return msg ?? "Request failed (\(code))"
        case .notSignedIn: return "Sign in to use this feature."
        case .invalidResponse: return "Unexpected response from YouTube Music."
        }
    }
}

/// Supplies the cookies of the signed-in web session (shared with WKWebView).
public typealias CookieProvider = @Sendable () async -> [HTTPCookie]

/// Client for the YouTube Music InnerTube API (the same private API the web
/// app uses). Authentication piggybacks on the browser session cookies.
public actor YTMusicClient {
    public static let origin = "https://music.youtube.com"
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private let session: URLSession
    private var cookieProvider: CookieProvider?
    private var visitorData: String?
    public private(set) var language: String
    public private(set) var region: String

    public init(language: String = "en", region: String = "US", cookieProvider: CookieProvider? = nil) {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
        self.language = language
        self.region = region
        self.cookieProvider = cookieProvider
    }

    public func setCookieProvider(_ p: CookieProvider?) { cookieProvider = p }
    public func setLocale(language: String, region: String) {
        self.language = language
        self.region = region
    }
    public func resetVisitor() { visitorData = nil }

    static var clientVersion: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return "1.\(f.string(from: Date().addingTimeInterval(-86400))).01.00"
    }

    // MARK: - Transport

    private func authorization(cookies: [HTTPCookie]) -> String? {
        guard let sapisid = cookies.first(where: { $0.name == "SAPISID" })?.value
                ?? cookies.first(where: { $0.name == "__Secure-3PAPISID" })?.value else { return nil }
        let ts = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(ts) \(sapisid) \(Self.origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(ts)_\(hex)"
    }

    public func post(_ endpoint: String, body: [String: Any] = [:]) async throws -> JSON {
        var client: [String: Any] = [
            "clientName": "WEB_REMIX",
            "clientVersion": Self.clientVersion,
            "hl": language,
            "gl": region,
            "platform": "DESKTOP",
            "userAgent": Self.userAgent,
        ]
        if let v = visitorData { client["visitorData"] = v }
        var payload = body
        payload["context"] = ["client": client, "user": ["lockedSafetyMode": false]]

        var comps = URLComponents(string: "\(Self.origin)/youtubei/v1/\(endpoint)")!
        comps.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.origin, forHTTPHeaderField: "Origin")
        req.setValue(Self.origin, forHTTPHeaderField: "X-Origin")
        req.setValue(Self.origin + "/", forHTTPHeaderField: "Referer")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(Self.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        if let v = visitorData { req.setValue(v, forHTTPHeaderField: "X-Goog-Visitor-Id") }

        if let provider = cookieProvider {
            let cookies = await provider().filter { $0.domain.hasSuffix("youtube.com") }
            if !cookies.isEmpty {
                let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                req.setValue(header, forHTTPHeaderField: "Cookie")
                if let auth = authorization(cookies: cookies) {
                    req.setValue(auth, forHTTPHeaderField: "Authorization")
                    req.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
                }
            }
        }

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSON(data: data)) ?? .null
        guard (200..<300).contains(status) else {
            throw YTMusicError.http(status, json.path("error.message").string)
        }
        if visitorData == nil, let v = json.path("responseContext.visitorData").string { visitorData = v }
        return json
    }

    // MARK: - Browse

    public func browse(_ target: BrowseTarget) async throws -> BrowsePage {
        var body: [String: Any] = ["browseId": target.browseId]
        if let p = target.params { body["params"] = p }
        let json = try await post("browse", body: body)
        return Parser.browse(json, browseId: target.browseId)
    }

    public func browse(_ id: String, params: String? = nil) async throws -> BrowsePage {
        try await browse(BrowseTarget(browseId: id, params: params))
    }

    public func home(params: String? = nil) async throws -> BrowsePage {
        try await browse("FEmusic_home", params: params)
    }

    public func continuation(_ token: String, endpoint: String = "browse") async throws -> ContinuationResult {
        let json = try await post(endpoint, body: ["continuation": token])
        return Parser.continuation(json)
    }

    public func rawBrowse(_ id: String, params: String? = nil) async throws -> JSON {
        var body: [String: Any] = ["browseId": id]
        if let p = params { body["params"] = p }
        return try await post("browse", body: body)
    }

    // MARK: - Search

    public func search(_ query: String, params: String? = nil) async throws -> SearchResults {
        var body: [String: Any] = ["query": query]
        if let p = params { body["params"] = p }
        return Parser.search(try await post("search", body: body))
    }

    public func searchContinuation(_ token: String) async throws -> ContinuationResult {
        Parser.continuation(try await post("search", body: ["continuation": token]))
    }

    public func suggestions(_ input: String) async throws -> SearchSuggestions {
        Parser.suggestions(try await post("music/get_search_suggestions", body: ["input": input]))
    }

    // MARK: - Playback queue

    public func next(_ target: WatchTarget) async throws -> WatchQueue {
        var body: [String: Any] = [
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]
        if let v = target.videoId { body["videoId"] = v }
        if let p = target.playlistId { body["playlistId"] = p }
        if let p = target.params { body["params"] = p }
        if let i = target.index { body["index"] = i }
        return Parser.watchQueue(try await post("next", body: body))
    }

    public func nextContinuation(_ token: String, playlistId: String?) async throws -> WatchQueue {
        var body: [String: Any] = ["continuation": token, "isAudioOnly": true, "enablePersistentPlaylistPanel": true]
        if let p = playlistId { body["playlistId"] = p }
        return Parser.watchQueue(try await post("next", body: body))
    }

    public func lyrics(browseId: String) async throws -> Lyrics? {
        Parser.lyrics(try await post("browse", body: ["browseId": browseId]))
    }

    // MARK: - Account & library actions

    public func accountInfo() async throws -> AccountInfo? {
        Parser.account(try await post("account/account_menu"))
    }

    public func rate(videoId: String, _ status: LikeStatus) async throws {
        let ep: String
        switch status {
        case .like: ep = "like/like"
        case .dislike: ep = "like/dislike"
        case .indifferent: ep = "like/removelike"
        }
        _ = try await post(ep, body: ["target": ["videoId": videoId]])
    }

    /// Saves / removes an album or playlist from the library.
    public func setSaved(playlistId: String, _ saved: Bool) async throws {
        _ = try await post(saved ? "like/like" : "like/removelike", body: ["target": ["playlistId": playlistId]])
    }

    public func setSubscribed(channelId: String, _ subscribed: Bool) async throws {
        _ = try await post(subscribed ? "subscription/subscribe" : "subscription/unsubscribe",
                           body: ["channelIds": [channelId]])
    }

    @discardableResult
    public func createPlaylist(title: String, description: String = "", privacy: String = "PRIVATE",
                               videoIds: [String] = []) async throws -> String? {
        var body: [String: Any] = ["title": title, "description": description, "privacyStatus": privacy]
        if !videoIds.isEmpty { body["videoIds"] = videoIds }
        return try await post("playlist/create", body: body)["playlistId"].string
    }

    public func deletePlaylist(_ playlistId: String) async throws {
        _ = try await post("playlist/delete", body: ["playlistId": playlistId])
    }

    public func addToPlaylist(_ playlistId: String, videoIds: [String]) async throws {
        let actions = videoIds.map {
            ["action": "ACTION_ADD_VIDEO", "addedVideoId": $0, "dedupeOption": "DEDUPE_OPTION_SKIP"]
        }
        _ = try await post("browse/edit_playlist", body: ["playlistId": playlistId, "actions": actions])
    }

    public func removeFromPlaylist(_ playlistId: String, videoId: String, setVideoId: String) async throws {
        let action: [String: Any] = ["action": "ACTION_REMOVE_VIDEO", "setVideoId": setVideoId, "removedVideoId": videoId]
        _ = try await post("browse/edit_playlist", body: ["playlistId": playlistId, "actions": [action]])
    }
}
