# LeoTube

[![Build](https://github.com/9tong/leotube/actions/workflows/build.yml/badge.svg)](https://github.com/9tong/leotube/actions/workflows/build.yml)

A native macOS client for YouTube Music, built with SwiftUI and Liquid Glass (macOS 26+).

![Home](docs/screenshots/01-home.png)

## Build & run

```bash
scripts/build-app.sh          # release build → build/LeoTube.app
open build/LeoTube.app
```

To build a drag-to-install disk image:

```bash
scripts/make-dmg.sh           # → build/LeoTube-<version>.dmg
```

Every push to `main` builds the DMG on GitHub Actions; download it from the run's artifacts. Pushing a `v*` tag publishes a GitHub Release with the DMG attached.

The version number comes from `CFBundleShortVersionString` in `Resources/Info.plist`. The app is ad-hoc signed, not notarized. On another Mac, open it the first time with right-click → Open, or run `xattr -dr com.apple.quarantine /Applications/LeoTube.app`.

`scripts/build-app.sh debug` makes a debug build. You only need the Command Line Tools: the app builds with SwiftPM, and the script wraps it into an ad-hoc-signed `.app` and generates the icon on first run.

## How it works

| Layer | What it does |
|---|---|
| `Sources/YTMusicKit` | InnerTube (`WEB_REMIX`) client and parsers. Every renderer becomes a `MediaItem`, every container a `Shelf`, so Home, Explore, artists, moods, library and search all share one set of views. |
| `PlayerEngine` | A hidden `WKWebView` running the official YouTube Music web player, driven over a small JS bridge. YouTube handles stream signing, attestation, quality and Premium (no ads), and the native app owns the queue. |
| `PlaybackController` | Queue, shuffle/repeat, radio continuation, autoplay, lyrics, likes, and session restore. It also handles Now Playing / media keys through `NowPlayingCenter`. |
| `AuthManager` | You sign in on Google's real sign-in page. The cookies live in the default WebKit store, which the player also uses; API calls are signed with `SAPISIDHASH`. |

## Developer tools

- `swift run ytm-probe [home|explore|search <q>|browse <id>|next <videoId>]` runs the parsers against the live API.
- `LEOTUBE_DEBUG=1` logs the player-engine state.
- `LEOTUBE_DEBUG_TOUR=<dir>` walks through the main screens and saves a real window capture of each (Liquid Glass included).
- `LEOTUBE_DEBUG_PLAY=<videoId>` starts playback at launch.

## Notes

- Signed-out sessions may get YouTube's "Sign in to confirm you're not a bot" check. The app retries once with a fresh visitor session, then asks you to sign in.
- This project is not affiliated with Google or YouTube.
