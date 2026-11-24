import SwiftUI
import YTMusicKit

/// Immersive full-window player: a turntable, the controls and the playlist.
struct NowPlayingView: View {
    @Environment(AppModel.self) private var app
    @State private var tint: Color = Theme.accent
    /// Closed each time the page opens. Next to the turntable in wide windows,
    /// over it in narrow ones.
    @State private var panel: Panel? = ProcessInfo.processInfo.environment["LEOTUBE_DEBUG_NOWPLAYING_PANEL"].flatMap { Panel(rawValue: $0.replacingOccurrences(of: "-open", with: "")) }

    private enum Panel: String {
        case queue, library
    }

    private static let panelShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    private static let wideWidth: CGFloat = 820

    var body: some View {
        let p = app.player
        GeometryReader { geo in
            let wide = geo.size.width > Self.wideWidth
            let panelWidth = min(400, max(300, geo.size.width * 0.34))
            ZStack {
                background(p.current)

                HStack(spacing: 36) {
                    player(p, width: geo.size.width - 72 - (wide && panel != nil ? panelWidth + 36 : 0), height: geo.size.height)
                        .frame(maxWidth: .infinity)

                    if wide, let panel {
                        content(of: panel)
                            .glassEffect(.regular, in: Self.panelShape)
                            .frame(width: panelWidth)
                            .padding(.top, 76)
                            .padding(.bottom, 32)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 36)

                if !wide, let panel {
                    Color.black.opacity(0.3)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.smooth(duration: 0.4)) { self.panel = nil } }
                        .transition(.opacity)
                    // Opaque: glass would blur the turning record again every frame.
                    content(of: panel)
                        .background(Color(white: 0.11), in: Self.panelShape)
                        .overlay(Self.panelShape.strokeBorder(.white.opacity(0.1)))
                        .frame(width: min(380, geo.size.width - 80))
                        .padding(.top, 72)
                        .padding([.bottom, .trailing], 20)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                header(p)
            }
        }
        .environment(\.colorScheme, .dark)
        .dominantColor(of: p.current?.artwork, into: $tint)
        .onExitCommand { if let panel { toggle(panel) } else { close() } }
        .onAppear {
            if app.inspectorTab == .related { app.inspectorTab = .queue }
        }
    }

    // MARK: - Parts

    private func player(_ p: PlaybackController, width: CGFloat, height: CGFloat) -> some View {
        // Short windows drop the volume and tighten up so the turntable stays.
        let compact = height < 700
        let chrome: CGFloat = compact ? 290 : 372
        let deckHeight = max(150, min(height - chrome, 640))
        let deckWidth = min(width, deckHeight * Turntable.aspectRatio)
        let textWidth = min(max(deckWidth, 380), width)
        return VStack(spacing: compact ? 16 : 24) {
            Turntable()
                .frame(width: deckWidth, height: deckWidth / Turntable.aspectRatio)
                .padding(.bottom, compact ? 6 : 14)
            if let item = p.current {
                title(item)
                    .frame(width: textWidth)
                    .id(item.id)
                    .transition(.blurReplace)
            }
            PlaybackProgress(height: 5).frame(width: min(textWidth + 40, width))
            TransportControls(scale: compact ? 1.15 : 1.35)
            if !compact { VolumeControl(width: 160) }
        }
        .animation(.smooth(duration: 0.5), value: p.current?.id)
        .padding(.top, 44)
    }

    private func title(_ item: MediaItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 24, weight: .heavy))
                    .lineLimit(1)
                ArtistLinksText(artists: item.artists, fallback: item.subtitle,
                                font: .system(size: 15, weight: .medium))
            }
            Spacer(minLength: 0)
            LikeButton(item: item, size: 20)
            Menu {
                ItemMenu(item: item)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).frame(width: 30, height: 30)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }

    private func content(of panel: Panel) -> some View {
        ZStack {
            switch panel {
            case .queue: QueuePanel().transition(.opacity)
            case .library: LibraryPanel().transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(Self.panelShape)
    }

    private func header(_ p: PlaybackController) -> some View {
        VStack {
            ZStack {
                if let source = p.sourceTitle {
                    VStack(spacing: 2) {
                        Text("PLAYING FROM").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        Text(source).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 108)
                }
                HStack(spacing: 10) {
                    GlassIconButton(systemName: "chevron.down", size: 40, help: "Close (Esc)") { close() }
                    Spacer()
                    panelButton(.library, "square.stack.fill", "Library and Playlists")
                    panelButton(.queue, "list.bullet", "Up Next")
                }
            }
            Spacer()
        }
        .padding(20)
    }

    private func panelButton(_ which: Panel, _ symbol: String, _ name: String) -> some View {
        GlassIconButton(systemName: symbol, size: 40, tint: panel == which ? Theme.accent.opacity(0.7) : nil,
                        help: panel == which ? "Hide \(name)" : name) { toggle(which) }
    }

    private func toggle(_ which: Panel) {
        withAnimation(.smooth(duration: 0.45)) { panel = panel == which ? nil : which }
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
