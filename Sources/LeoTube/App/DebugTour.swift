import AppKit
import SwiftUI
import YTMusicKit

/// Development aid: `LEOTUBE_DEBUG_TOUR=/some/dir` walks through the main
/// screens and writes a window snapshot of each to that directory.
@MainActor
enum DebugTour {
    static func runIfRequested(_ app: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_TOUR"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        app.showWelcome = false
        Task { @MainActor in
            @MainActor func shot(_ name: String, wait: Double = 5) async {
                try? await Task.sleep(for: .seconds(wait))
                snapshot(to: out.appendingPathComponent("\(name).png"))
            }
            if ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_WELCOME"] != nil {
                app.showWelcome = true
                await shot("00-welcome", wait: 3)
                app.showWelcome = false
            }
            let size = (ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_TOUR_SIZE"] ?? "1480x920")
                .split(separator: "x").compactMap { Double($0) }
            if size.count == 2, let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 && $0.alphaValue > 0 }) {
                w.setFrame(NSRect(x: 40, y: 40, width: size[0], height: size[1]), display: true)
            }
            app.selection = .home
            await shot("01-home", wait: 7)
            app.selection = .explore
            await shot("02-explore")
            app.push(BrowseTarget(browseId: "MPREb_L64BnYDQpHZ"))
            await shot("03-album")
            app.path = []
            app.push(BrowseTarget(browseId: "UCPC0L1d253x-KuMNwa05TpA"))
            await shot("04-artist")
            app.push(BrowseTarget(browseId: "VLPLkpaQgbH2nStd0401Ul7-ffbGc-equxdB"))
            await shot("05-playlist")
            app.selection = .search
            await shot("06-search-browse")
            app.search("taylor swift")
            await shot("07-search-results")
            app.selection = .library
            await shot("08-library", wait: 3)
            if let i = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_QUEUE_AT"].flatMap(Int.init) {
                app.player.debugSetIndex(i)
            }
            app.showQueuePopover = true
            app.selection = .home
            await shot("09-home-queue", wait: 4)
            if let pop = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }) {
                snapshot(window: pop, to: out.appendingPathComponent("09b-queue-popover.png"))
            }
            app.showQueuePopover = false
            app.showNowPlaying = true
            await shot("10-now-playing", wait: 4)
            app.showNowPlaying = false
            app.showLogin = true
            try? await Task.sleep(for: .seconds(8))
            if let sheet = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 && $0.alphaValue > 0 })?.attachedSheet {
                snapshot(window: sheet, to: out.appendingPathComponent("11-login.png"))
            }
            app.showLogin = false
            NSLog("[tour] done")
        }
    }

    private typealias CreateImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func snapshot(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 && $0.alphaValue > 0 }) else { return }
        snapshot(window: window, to: url)
    }

    static func snapshot(window: NSWindow, to url: URL) {
        // Prefer the real composited window (includes Liquid Glass).
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: CreateImageFn.self)
            // kCGWindowListOptionIncludingWindow = 1 << 3, kCGWindowImageBoundsIgnoreFraming = 1 << 0
            if let img = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue(), img.width > 10 {
                try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
                NSLog("[tour] wrote %@ (composited)", url.path)
                return
            }
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        NSLog("[tour] wrote %@", url.path)
    }

    /// Scrolls the queue pop-up's list at 60 fps for 6 s and reports frames
    /// that took noticeably longer than one display frame (hitches).
    static func scrollTest(label: String) async {
        guard let pop = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }),
              let scroll = findScrollView(pop.contentView) else { NSLog("[scroll] no popover list"); return }
        let clip = scroll.contentView
        let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - clip.bounds.height)
        var y: CGFloat = 0, dir: CGFloat = 1
        var last = CACurrentMediaTime(), hitches = 0, worst = 0.0, frames = 0, slow = 0, total = 0.0
        let end = last + 6
        while CACurrentMediaTime() < end {
            y += dir * 6
            if y > maxY || y < 0 { dir = -dir; y = min(max(y, 0), maxY) }
            clip.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(clip)
            try? await Task.sleep(for: .milliseconds(16))
            let now = CACurrentMediaTime()
            let dt = (now - last) * 1000
            if dt > 33 { hitches += 1 }
            if dt > 20 { slow += 1 }
            total += dt
            worst = max(worst, dt)
            frames += 1
            last = now
        }
        NSLog("[scroll] %@: %d frames, avg %.1f ms, %d slow (>20ms), %d hitches (>33ms), worst %.0f ms", label, frames, total / Double(max(frames, 1)), slow, hitches, worst)
    }

    private static func findScrollView(_ view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let s = view as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height { return s }
        for sub in view.subviews { if let s = findScrollView(sub) { return s } }
        return nil
    }
}
