import SwiftUI
import YTMusicKit

/// Immersive full-window player with artwork-tinted ambience.
struct NowPlayingView: View {
    @Environment(AppModel.self) private var app
    @State private var tint: Color = Theme.accent

    var body: some View {
        let p = app.player
        GeometryReader { geo in
            let wide = geo.size.width > 980
            ZStack {
                background(p.current)

                HStack(spacing: 44) {
                    VStack(spacing: 26) {
                        Spacer(minLength: 0)
                        let side = min(geo.size.height * 0.5, wide ? 500 : 440, geo.size.width * (wide ? 0.4 : 0.7))
                        ArtworkView(artwork: p.current?.artwork, size: 1200, cornerRadius: 22)
                            .frame(width: side, height: side)
                            .shadow(color: .black.opacity(0.5), radius: 40, y: 24)
                            .scaleEffect(p.isPlaying ? 1 : 0.92)
                            .animation(.spring(duration: 0.6, bounce: 0.25), value: p.isPlaying)
                            .id(p.current?.id)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))

                        if let item = p.current {
                            HStack(alignment: .center, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 26, weight: .heavy))
                                        .lineLimit(1)
                                    ArtistLinksText(artists: item.artists, fallback: item.subtitle,
                                                    font: .system(size: 16, weight: .medium))
                                }
                                Spacer()
                                LikeButton(item: item, size: 20)
                                Menu {
                                    ItemMenu(item: item)
                                } label: {
                                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).frame(width: 30, height: 30)
                                }
                                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            }
                            .frame(width: side)
                        }

                        PlaybackProgress(height: 5).frame(width: min(side + 80, 600))
                        TransportControls(scale: 1.35)
                        VolumeControl(width: 160)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)

                    if wide {
                        QueuePanel()
                            .frame(width: min(420, geo.size.width * 0.34))
                            .frame(maxHeight: geo.size.height - 140)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 40)

                VStack {
                    HStack {
                        GlassIconButton(systemName: "chevron.down", size: 40, help: "Close (Esc)") { close() }
                        Spacer()
                        if let s = p.sourceTitle {
                            VStack(spacing: 2) {
                                Text("PLAYING FROM").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                                Text(s).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            }
                            .frame(maxWidth: 380)
                        }
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    Spacer()
                }
                .padding(20)
            }
        }
        .environment(\.colorScheme, .dark)
        .dominantColor(of: p.current?.artwork, into: $tint)
        .onExitCommand { close() }
        .onAppear {
            if app.inspectorTab == .related { app.inspectorTab = .queue }
        }
    }

    private func close() {
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { app.showNowPlaying = false }
    }

    private func background(_ item: MediaItem?) -> some View {
        ZStack {
            Color.black
            ArtworkView(artwork: item?.artwork, size: 300, cornerRadius: 0)
                .scaleEffect(1.9)
                .rotationEffect(.degrees(4))
                .blur(radius: 90)
                .opacity(0.85)
            LinearGradient(colors: [tint.opacity(0.55), .black.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(0.25)
        }
        .ignoresSafeArea()
        .clipped()
    }
}
