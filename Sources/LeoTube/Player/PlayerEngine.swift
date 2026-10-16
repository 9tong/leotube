import AppKit
import WebKit
import YTMusicKit

struct EngineState: Equatable {
    var ready = false
    var time: Double = 0
    var duration: Double = 0
    var paused = true
    var buffering = false
    var videoId: String?
    var isAd = false
    var error: String?
}

/// Audio engine backed by an invisible YouTube Music web player.
///
/// Streams from YouTube are signed, throttled and protected in ways that change
/// often; letting the official web player handle them is the only robust way
/// to get full-quality, Premium-aware playback. The UI never shows this view –
/// it is driven entirely through a small JavaScript bridge.
@MainActor
final class PlayerEngine: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum Event { case ended, play, pause }

    let webView: WKWebView
    private let hostWindow: NSWindow
    private var pollTimer: Timer?
    private(set) var expectedVideoId: String?
    private var loadIssuedAt = Date.distantPast
    private var volume: Double = 0.8
    private var lastState = EngineState()
    /// Videos already retried with a full page load after an in-app load failed.
    private var pageLoadRetried: Set<String> = []
    /// The video an "ended" event was already reported for, so a track can
    /// only finish once however many signals (JS, polling, guard) notice it.
    private var endedReportedFor: String?

    static let debug = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG"] != nil
    /// Test hook: disables both early-end mechanisms, so a track plays to its
    /// real end and the web app's autoplay (and the guard) can be exercised.
    static let debugNoEarlyEnd = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_NO_EARLY_END"] != nil
    var onState: ((EngineState) -> Void)?
    var onEvent: ((Event) -> Void)?

    init(dataStore: WKWebsiteDataStore) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = false
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if Self.debugNoEarlyEnd {
            ucc.addUserScript(WKUserScript(source: "window.__ltNoEarlyEnd = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController = ucc

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 600), configuration: config)
        webView.customUserAgent = YTMusicClient.userAgent

        // Offscreen host window so the page counts as "in a window" (required
        // for media playback) without ever being visible to the user.
        hostWindow = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 960, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        hostWindow.isReleasedWhenClosed = false
        hostWindow.isExcludedFromWindowsMenu = true
        hostWindow.ignoresMouseEvents = true
        hostWindow.alphaValue = 0
        hostWindow.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        hostWindow.contentView = webView

        super.init()
        ucc.add(WeakMessageHandler(self), name: "lt")
        webView.navigationDelegate = self
    }

    /// Attached lazily: a window existing at launch would stop SwiftUI from
    /// opening the main window.
    private func ensureHosted() {
        if !hostWindow.isVisible { hostWindow.orderFrontRegardless() }
    }

    // MARK: - Commands

    func warmUp() {
        ensureHosted()
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
        startPolling()
    }

    func load(videoId: String, playlistId: String?) {
        if expectedVideoId != videoId {
            pageLoadRetried.removeAll()
            endedReportedFor = nil
        }
        expectedVideoId = videoId
        loadIssuedAt = Date()
        ensureHosted()
        startPolling()
        Task {
            let ok = (try? await webView.callAsyncJavaScript(
                "return window.__lt ? window.__lt.load(id, vol) : false",
                arguments: ["id": videoId, "vol": volume], in: nil, contentWorld: .page)) as? Bool ?? false
            if !ok { loadPage(videoId) }
        }
    }

    private func loadPage(_ videoId: String) {
        var c = URLComponents(string: "https://music.youtube.com/watch")!
        c.queryItems = [URLQueryItem(name: "v", value: videoId)]
        webView.load(URLRequest(url: c.url!))
    }

    func play() { run("window.__lt && window.__lt.play()") }
    func pause() { run("window.__lt && window.__lt.pause()") }
    func stop() {
        expectedVideoId = nil
        pause()
    }

    func seek(to seconds: Double) {
        Task { _ = try? await webView.callAsyncJavaScript("window.__lt && window.__lt.seek(t)", arguments: ["t": seconds], in: nil, contentWorld: .page) }
    }

    func setVolume(_ v: Double) {
        volume = v
        Task { _ = try? await webView.callAsyncJavaScript("window.__lt && window.__lt.volume(v)", arguments: ["v": v], in: nil, contentWorld: .page) }
    }

    private func run(_ js: String) {
        Task { _ = try? await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page) }
    }

    // MARK: - State polling

    private func startPolling() {
        guard pollTimer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() async {
        guard let dict = (try? await webView.callAsyncJavaScript(
            "return window.__lt ? window.__lt.state() : null", arguments: [:], in: nil, contentWorld: .page)) as? [String: Any]
        else { return }
        var s = EngineState()
        s.ready = dict["ready"] as? Bool ?? false
        s.time = (dict["t"] as? NSNumber)?.doubleValue ?? 0
        s.duration = (dict["d"] as? NSNumber)?.doubleValue ?? 0
        s.paused = dict["paused"] as? Bool ?? true
        s.buffering = dict["buffering"] as? Bool ?? false
        s.videoId = dict["vid"] as? String
        s.isAd = dict["ad"] as? Bool ?? false
        s.error = dict["err"] as? String

        // In-app loads can be rejected (e.g. bot checks for signed-out
        // sessions) or stall at 0:00 where a full page load succeeds: retry
        // once that way.
        let stalled = s.videoId == expectedVideoId && !s.isAd && s.time < 0.5 && (s.buffering || s.duration == 0)
            && Date().timeIntervalSince(loadIssuedAt) > 8
        if s.error != nil || stalled, let expected = expectedVideoId, s.videoId == expected, !pageLoadRetried.contains(expected) {
            if Self.debug { NSLog("[engine] retrying %@ with a page load (%@)", expected, s.error ?? "stalled") }
            pageLoadRetried.insert(expected)
            loadIssuedAt = Date()
            loadPage(expected)
            return
        }
        // Still stuck after the page-load retry: surface it as an error so the
        // queue can move on (or stop after repeated failures).
        if stalled, s.error == nil, let expected = expectedVideoId, pageLoadRetried.contains(expected),
           Date().timeIntervalSince(loadIssuedAt) > 15 {
            s.error = "The song didn’t start"
        }

        // Backup for the bridge's early pause (its timeupdate events can be
        // throttled in the background): finish the track ourselves in its last
        // second, before the web app's own autoplay can start something else.
        if !Self.debugNoEarlyEnd, let expected = expectedVideoId, s.videoId == expected, !s.isAd, !s.paused,
           s.duration > 2, s.duration - s.time < 0.9 {
            reportEnded(pausing: true)
        }

        // Our queue is the source of truth. If the web app is still showing a
        // different video well after our load, re-assert ours. (This never
        // advances the queue — that only happens via reportEnded.)
        if let expected = expectedVideoId, let vid = s.videoId, vid != expected, !s.isAd,
           Date().timeIntervalSince(loadIssuedAt) > 4 {
            loadIssuedAt = Date()
            load(videoId: expected, playlistId: nil)
            return
        }
        // Never report a foreign video's progress.
        if let expected = expectedVideoId, s.videoId != nil, s.videoId != expected, !s.isAd {
            s.time = 0; s.duration = 0
        }
        if Self.debug { NSLog("[engine] ready=%d t=%.1f d=%.1f paused=%d buf=%d vid=%@ expected=%@ ad=%d err=%@ url=%@", s.ready ? 1 : 0, s.time, s.duration, s.paused ? 1 : 0, s.buffering ? 1 : 0, s.videoId ?? "-", expectedVideoId ?? "-", s.isAd ? 1 : 0, s.error ?? "-", webView.url?.absoluteString ?? "-") }
        if s != lastState {
            lastState = s
            onState?(s)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if Self.debug { NSLog("[engine-msg] %@", String(describing: body)) }
        switch type {
        case "ended":
            if let vid = body["vid"] as? String, let expected = expectedVideoId, vid != expected { return }
            reportEnded(pausing: false)
        case "foreign":
            // The web app started a video we didn't ask for (its autoplay); the
            // bridge has already paused and muted it. If our track was at its
            // end, that's a missed "ended"; otherwise put our track back.
            guard let expected = expectedVideoId else { return }
            let nearEnd = lastState.videoId == expected && lastState.duration > 0 && lastState.duration - lastState.time < 6
            if nearEnd {
                reportEnded(pausing: false)
            } else if Date().timeIntervalSince(loadIssuedAt) > 1.5 {
                load(videoId: expected, playlistId: nil)
            }
        case "play": onEvent?(.play)
        case "pause": onEvent?(.pause)
        case "log": NSLog("[LeoTube web] %@", String(describing: body["msg"] ?? ""))
        default: break
        }
    }

    private func reportEnded(pausing: Bool) {
        guard let expected = expectedVideoId, endedReportedFor != expected else { return }
        endedReportedFor = expected
        if pausing { pause() }
        if Self.debug { NSLog("[engine] ended %@ (native=%d)", expected, pausing ? 1 : 0) }
        onEvent?(.ended)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let expected = expectedVideoId {
            // A full page load starts a fresh bridge: tell it which video is ours.
            Task {
                _ = try? await webView.callAsyncJavaScript("if (window.__lt) window.__lt.expected = id",
                                                          arguments: ["id": expected], in: nil, contentWorld: .page)
            }
        } else {
            run("window.__lt && window.__lt.pause()")
        }
    }

    // MARK: - Bridge

    private static let bridgeScript = #"""
    (function () {
      if (window.__lt) return;
      const post = (m) => { try { window.webkit.messageHandlers.lt.postMessage(m); } catch (e) {} };
      const lt = window.__lt = {
        expected: null, endSent: false, vol: 0.8,
        player() { return document.getElementById('movie_player'); },
        video() { return document.querySelector('video'); },
        isAd() { const p = this.player(); return !!(p && p.classList && p.classList.contains('ad-showing')); },
        currentVid() { try { const p = this.player(); return p && p.getVideoData ? p.getVideoData().video_id : null; } catch (e) { return null; } },
        load(id, vol) {
          const p = this.player();
          this.expected = id; this.endSent = false; this.lastForeign = null;
          if (typeof vol === 'number') this.vol = vol;
          const app = document.querySelector('ytmusic-app');
          if (app && p) {
            // Navigate inside the web app so it performs its own (attested) player request.
            app.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true,
              detail: { endpoint: { watchEndpoint: { videoId: id } } } }));
            setTimeout(() => this.volume(this.vol), 600);
            setTimeout(() => this.volume(this.vol), 1800);
            return true;
          }
          if (p && typeof p.loadVideoById === 'function') {
            p.loadVideoById(id);
            setTimeout(() => this.volume(this.vol), 400);
            setTimeout(() => this.volume(this.vol), 1500);
            return true;
          }
          return false;
        },
        play() { const v = this.video(); if (v) { v.play().catch(() => {}); } else { const p = this.player(); p && p.playVideo && p.playVideo(); } },
        pause() { const v = this.video(); if (v) v.pause(); },
        seek(t) { const p = this.player(); this.endSent = false; if (p && p.seekTo) p.seekTo(t, true); else { const v = this.video(); if (v) v.currentTime = t; } },
        volume(x) {
          this.vol = x;
          const p = this.player();
          if (p && p.setVolume) { p.setVolume(Math.round(x * 100)); if (p.unMute) p.unMute(); }
          const v = this.video(); if (v) { v.volume = x; v.muted = false; }
        },
        state() {
          const v = this.video(), p = this.player();
          let err = null;
          try {
            const r = p && p.getPlayerResponse ? p.getPlayerResponse() : null;
            const st = r && r.playabilityStatus;
            if (st && st.status && st.status !== 'OK' && st.status !== 'LIVE_STREAM_OFFLINE') err = st.reason || st.status;
          } catch (e) {}
          return {
            ready: !!(p && typeof p.loadVideoById === 'function'),
            t: v ? v.currentTime : 0,
            d: v && isFinite(v.duration) ? v.duration : 0,
            paused: v ? v.paused : true,
            buffering: v ? (v.readyState < 3 && !v.paused) : false,
            vid: this.currentVid(),
            ad: this.isAd(),
            err: err
          };
        }
      };

      // Finish a track slightly early and pause, so the web app's own autoplay
      // never kicks in; the native queue decides what plays next.
      // Ads swap media under the same element; ignore end signals around them.
      lt.adSeenAt = 0;
      setInterval(() => {
        if (lt.isAd()) { lt.adSeenAt = Date.now(); lt.endSent = false; }
      }, 250);
      const nearAd = () => lt.isAd() || Date.now() - lt.adSeenAt < 2500;
      document.addEventListener('timeupdate', (e) => {
        const v = e.target;
        if (!(v instanceof HTMLMediaElement) || lt.endSent || nearAd() || !lt.expected || window.__ltNoEarlyEnd) return;
        if (isFinite(v.duration) && v.duration > 2 && v.duration - v.currentTime < 0.6) {
          lt.endSent = true; v.pause();
          post({ type: 'ended', vid: lt.currentVid() });
        }
      }, true);
      document.addEventListener('ended', (e) => {
        if (!(e.target instanceof HTMLMediaElement) || lt.endSent || nearAd() || window.__ltNoEarlyEnd) return;
        lt.endSent = true; post({ type: 'ended', vid: lt.currentVid() });
      }, true);
      // Guard: if the web app starts a video we didn't ask for (its own
      // autoplay / queue), silence it at once and let the native queue decide.
      const guardForeign = (e) => {
        const v = e.target;
        if (!(v instanceof HTMLMediaElement) || !lt.expected || lt.isAd()) return;
        const vid = lt.currentVid();
        if (vid && vid !== lt.expected) {
          v.muted = true; v.pause(); lt.mutedForeign = true;
          if (lt.lastForeign !== vid) { lt.lastForeign = vid; post({ type: 'foreign', vid: vid }); }
        } else if (vid === lt.expected && lt.mutedForeign) {
          lt.mutedForeign = false; lt.lastForeign = null; v.muted = false;
        }
      };
      ['play', 'playing', 'loadeddata', 'timeupdate'].forEach((t) => document.addEventListener(t, guardForeign, true));
      document.addEventListener('play', (e) => { if (e.target instanceof HTMLMediaElement) post({ type: 'play' }); }, true);
      document.addEventListener('pause', (e) => { if (e.target instanceof HTMLMediaElement) post({ type: 'pause' }); }, true);

      // Keep media keys and Now Playing under native control.
      try {
        if (navigator.mediaSession) {
          navigator.mediaSession.setActionHandler = function () {};
          Object.defineProperty(navigator.mediaSession, 'metadata', { set() {}, get() { return null; } });
        }
      } catch (e) {}

      // Auto-dismiss "Are you still listening?" prompts.
      setInterval(() => {
        const d = document.querySelector('ytmusic-you-there-renderer');
        if (d) { const b = d.querySelector('button, yt-button-renderer, .yt-spec-button-shape-next'); if (b) b.click(); }
      }, 2000);
    })();
    """#
}

/// Breaks the retain cycle between WKUserContentController and its handler.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}
