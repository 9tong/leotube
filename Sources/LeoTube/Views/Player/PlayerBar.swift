import SwiftUI
import YTMusicKit

/// Floating Liquid Glass player at the bottom of the window.
struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    /// Width actually available to the bar, so it can adapt to narrow
    /// windows (e.g. macOS Split View) instead of forcing the window wider.
    @State private var width: CGFloat = 1000

    private enum Layout { case regular, compact, mini }
    private var layout: Layout { width >= 860 ? .regular : (width >= 640 ? .compact : .mini) }

    var body: some View {
        let p = app.player
        Group {
            switch layout {
            case .regular:
                HStack(spacing: 18) {
                    nowPlaying(p)
                        .frame(maxWidth: 330, alignment: .leading)
                    VStack(spacing: 2) {
                        TransportControls()
                        PlaybackProgress()
                    }
                    .frame(minWidth: 300, maxWidth: 580)
                    .layoutPriority(1)
                    trailing(volume: true)
                        .frame(maxWidth: 330, alignment: .trailing)
                }
            case .compact:
                HStack(spacing: 12) {
                    nowPlaying(p, showLike: false)
                        .frame(maxWidth: 260, alignment: .leading)
                    VStack(spacing: 2) {
                        TransportControls(showModes: width >= 720)
                        PlaybackProgress()
                    }
                    .frame(minWidth: 200, maxWidth: 340)
                    .layoutPriority(1)
                    trailing(volume: false)
                }
            case .mini:
                // Two rows so the full progress bar (times + scrubbing) fits.
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        nowPlaying(p, showLike: false, artworkSize: 44)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MiniTransport()
                        queueButton
                    }
                    PlaybackProgress(labelFont: .system(size: 10, weight: .medium).monospacedDigit(), height: 3)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: layout == .mini ? 92 : Theme.playerBarHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    @ViewBuilder private func nowPlaying(_ p: PlaybackController, showLike: Bool = true, artworkSize: CGFloat = 52) -> some View {
        if let item = p.current {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(duration: 0.5, bounce: 0.15)) { app.showNowPlaying = true }
                } label: {
                    ArtworkView(artwork: item.artwork, size: 160, cornerRadius: 10)
                        .frame(width: artworkSize, height: artworkSize)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(4)
                                .background(.black.opacity(0.5), in: Circle())
                                .foregroundStyle(.white)
                                .padding(3)
                                .opacity(0.9)
                        }
                }
                .buttonStyle(PressScaleStyle())
                .help("Open Now Playing")

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if p.isAd {
                            Text("AD").font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.yellow, in: Capsule()).foregroundStyle(.black)
                        }
                        Text(item.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    if app.playbackNeedsSignIn && !app.auth.isSignedIn {
                        Button("Sign in to play") { app.showLogin = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    } else {
                        ArtistLinksText(artists: item.artists, fallback: item.subtitle)
                    }
                }
                if showLike {
                    LikeButton(item: item, size: 14)
                        .padding(.leading, 2)
                }
            }
            .contextMenu { ItemMenu(item: item) }
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: artworkSize, height: artworkSize)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.tertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Playing").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text("Pick something to listen to").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func trailing(volume: Bool) -> some View {
        HStack(spacing: 14) {
            panelButton("quote.bubble", tab: .lyrics, help: "Lyrics")
            queueButton
            if volume {
                ViewThatFits {
                    VolumeControl(width: 88)
                    VolumeControl(width: 44)
                }
            }
            Button {
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) { app.showNowPlaying = true }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PressScaleStyle())
            .disabled(app.player.current == nil)
            .help("Full Screen Player")
        }
    }

    private var queueButton: some View {
        @Bindable var app = app
        return Button {
            app.showQueuePopover.toggle()
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(app.showQueuePopover ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help("Queue")
        .popover(isPresented: $app.showQueuePopover, arrowEdge: .top) {
            QueuePopover().environment(app)
        }
    }

    private func panelButton(_ symbol: String, tab: InspectorTab, help: String) -> some View {
        let active = app.showInspector && app.inspectorTab == tab
        return Button {
            withAnimation(.spring(duration: 0.35)) { app.toggleInspector(tab) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
    }
}

/// Previous / play / next for the smallest player bar.
private struct MiniTransport: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.player
        HStack(spacing: 6) {
            Button { p.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14, weight: .semibold)).frame(width: 26, height: 26)
            }
            .buttonStyle(PressScaleStyle())
            Button { p.togglePlayPause() } label: {
                ZStack {
                    Circle().fill(.white)
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: p.isPlaying ? 0 : 1)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(PressScaleStyle())
            Button { p.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14, weight: .semibold)).frame(width: 26, height: 26)
            }
            .buttonStyle(PressScaleStyle())
        }
        .disabled(p.current == nil)
    }
}
