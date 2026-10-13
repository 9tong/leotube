import Foundation
import Observation
import WebKit
import YTMusicKit

/// Owns the browser session used for both API calls and playback. Signing in
/// happens in a real Google sign-in page; the resulting cookies live in the
/// default WebKit data store and are shared with the player web view.
@MainActor
@Observable
final class AuthManager {
    private(set) var isSignedIn = false
    private(set) var hasChecked = false
    var account: AccountInfo?

    let dataStore = WKWebsiteDataStore.default()

    static let signInURL: URL = {
        let next = "https://music.youtube.com/"
        let cont = "https://www.youtube.com/signin?action_handle_signin=true&app=desktop&next=" +
            (next.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? next)
        var c = URLComponents(string: "https://accounts.google.com/ServiceLogin")!
        c.queryItems = [
            URLQueryItem(name: "service", value: "youtube"),
            URLQueryItem(name: "uilel", value: "3"),
            URLQueryItem(name: "passive", value: "true"),
            URLQueryItem(name: "continue", value: cont),
        ]
        return c.url!
    }()

    func cookies() async -> [HTTPCookie] {
        await dataStore.httpCookieStore.allCookies()
    }

    @discardableResult
    func refresh() async -> Bool {
        let all = await cookies()
        isSignedIn = all.contains { ($0.name == "SAPISID" || $0.name == "__Secure-3PAPISID") && $0.domain.hasSuffix("youtube.com") }
        hasChecked = true
        if !isSignedIn { account = nil }
        return isSignedIn
    }

    func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let targets = records.filter { r in
            ["youtube", "google", "gstatic", "ggpht", "youtu.be"].contains { r.displayName.contains($0) }
        }
        await dataStore.removeData(ofTypes: types, for: targets)
        isSignedIn = false
        account = nil
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var s = CharacterSet.urlQueryAllowed
        s.remove(charactersIn: "&=?+/:")
        return s
    }()
}
