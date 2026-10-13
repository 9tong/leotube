import AppKit
import SwiftUI

@main
struct LeoTubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()

    var body: some Scene {
        Window("LeoTube", id: "main") {
            RootView()
                .environment(app)
                .task {
                    delegate.app = app
                    await app.bootstrap()
                }
        }
        .defaultSize(width: 1480, height: 920)
        .windowToolbarStyle(.unified)
        .commands { PlaybackCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
                .preferredColorScheme(app.appearance.colorScheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppModel?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Space toggles playback unless a text field is focused.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty,
                  !(event.window?.firstResponder is NSText),
                  let app = self?.app else { return event }
            MainActor.assumeIsolated { app.player.togglePlayPause() }
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { app?.player.saveSession() }
    }
}

struct PlaybackCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { app.beginNewPlaylist() }
                .keyboardShortcut("n")
        }
        CommandMenu("Controls") {
            Button(app.player.isPlaying ? "Pause" : "Play") { app.player.togglePlayPause() }
            Button("Next") { app.player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { app.player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Skip Forward 10s") { app.player.skip(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Skip Back 10s") { app.player.skip(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            Button("Volume Up") { app.player.volume = min(1, app.player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { app.player.volume = max(0, app.player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Toggle("Shuffle", isOn: Binding(get: { app.player.shuffle }, set: { _ in app.player.toggleShuffle() }))
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Repeat: \(app.player.repeatMode.rawValue.capitalized)") { app.player.repeatMode = app.player.repeatMode.next }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Like Current Song") { if let c = app.player.current { app.player.toggleLike(c) } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            Button("Home") { app.selection = .home }.keyboardShortcut("1")
            Button("Explore") { app.selection = .explore }.keyboardShortcut("2")
            Button("Library") { app.selection = .library }.keyboardShortcut("3")
            Button("Search") { app.selection = .search }.keyboardShortcut("f")
            Divider()
            Button("Show Queue") { app.showQueuePopover.toggle() }.keyboardShortcut("u", modifiers: [.command, .option])
            Button("Show Lyrics") { app.toggleInspector(.lyrics) }.keyboardShortcut("l", modifiers: [.command, .option])
            Button(app.showNowPlaying ? "Close Now Playing" : "Now Playing") {
                withAnimation(.spring(duration: 0.5)) { app.showNowPlaying.toggle() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
        }
    }
}
