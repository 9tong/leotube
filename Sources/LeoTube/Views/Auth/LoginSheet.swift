import SwiftUI
import WebKit
import YTMusicKit

/// Google sign-in in an embedded browser sharing the app's WebKit session.
struct LoginSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var finishing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sign in to YouTube Music").font(.system(size: 14, weight: .bold))
                    Text("Your account stays on this Mac — LeoTube talks to Google directly.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if loading || finishing { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            SignInWebView(dataStore: app.auth.dataStore, loading: $loading) {
                guard !finishing else { return }
                finishing = true
                Task { await app.didSignIn() }
            }
        }
        .frame(width: 520, height: 700)
    }
}

private struct SignInWebView: NSViewRepresentable {
    let dataStore: WKWebsiteDataStore
    @Binding var loading: Bool
    var onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.customUserAgent = YTMusicClient.userAgent
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: AuthManager.signInURL))
        context.coordinator.startObserving(dataStore.httpCookieStore)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let parent: SignInWebView
        private var done = false
        private weak var store: WKHTTPCookieStore?

        init(_ parent: SignInWebView) { self.parent = parent }

        func startObserving(_ store: WKHTTPCookieStore) {
            self.store = store
            store.add(self)
        }

        deinit { store?.remove(self) }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            if PlayerEngine.debug {
                webView.evaluateJavaScript("document.title + ' | ' + document.body.innerText.slice(0, 300)") { r, _ in
                    NSLog("[login] finished %@ :: %@", webView.url?.absoluteString ?? "-", String(describing: r ?? ""))
                }
            }
            if webView.url?.host()?.contains("music.youtube.com") == true { check(webView.configuration.websiteDataStore.httpCookieStore) }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check(cookieStore) }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[login] failed %@", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[login] failed provisional %@", error.localizedDescription)
        }

        private func check(_ store: WKHTTPCookieStore) {
            store.getAllCookies { [weak self] cookies in
                guard let self, !self.done else { return }
                let ok = cookies.contains { ($0.name == "SAPISID" || $0.name == "__Secure-3PAPISID") && $0.domain.hasSuffix("youtube.com") }
                if ok {
                    self.done = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.parent.onSignedIn() }
                }
            }
        }
    }
}

struct NewPlaylistSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var privacy = "PRIVATE"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Playlist").font(.system(size: 18, weight: .bold))
                    if !app.pendingPlaylistItems.isEmpty {
                        Text("Starting with \(app.pendingPlaylistItems.count == 1 ? "“\(app.pendingPlaylistItems[0].title)”" : "\(app.pendingPlaylistItems.count) items")")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical).lineLimit(2...4)
                Picker("Privacy", selection: $privacy) {
                    Text("Private").tag("PRIVATE")
                    Text("Unlisted").tag("UNLISTED")
                    Text("Public").tag("PUBLIC")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel") { app.pendingPlaylistItems = []; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    app.createPlaylist(title: title, description: description, privacy: privacy)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
