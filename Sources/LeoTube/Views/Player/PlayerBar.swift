import SwiftUI
import YTMusicKit

/// Floating Liquid Glass player at the bottom of the window.
struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    @Namespace private var ns

    var body: some View {
        let p = app.player
        HStack(spacing: 18) {
            nowPlaying(p)
                .frame(minWidth: 170, maxWidth: 330, alignment: .leading)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                TransportControls()
                PlaybackProgress()
                    .frame(maxWidth: 560)
            }
            .frame(minWidth: 250, maxWidth: 580)
            Spacer(minLength: 0)
            trailing
                .frame(minWidth: 150, maxWidth: 330, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.playerBarHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    @ViewBuilder private func nowPlaying(_ p: PlaybackController) -> some View {
        if let item = p.current {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(duration: 0.5, bounce: 0.15)) { app.showNowPlaying = true }
                } label: {
                    ArtworkView(artwork: item.artwork, size: 160, cornerRadius: 10)
                        .frame(width: 52, height: 52)
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
                LikeButton(item: item, size: 14)
                    .padding(.leading, 2)
            }
            .contextMenu { ItemMenu(item: item) }
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.tertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Playing").font(.system(size: 13.5, weight: .semibold))
                    Text("Pick something to listen to").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 14) {
            panelButton("quote.bubble", tab: .lyrics, help: "Lyrics")
            queueButton
            ViewThatFits {
                VolumeControl(width: 88)
                VolumeControl(width: 44)
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
