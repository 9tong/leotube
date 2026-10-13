import SwiftUI
import YTMusicKit

/// Right-hand panel with Up Next, Lyrics and Related tabs.
struct QueuePanel: View {
    @Environment(AppModel.self) private var app
    var compactHeader = false

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            Picker("", selection: $app.inspectorTab) {
                ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            switch app.inspectorTab {
            case .queue: QueueList()
            case .lyrics: LyricsView()
            case .related: RelatedView()
            }
        }
    }
}

/// The queue shown as a popover from the player bar.
struct QueuePopover: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.player
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Queue").font(.system(size: 17, weight: .bold))
                Spacer()
                if !p.upNext.isEmpty {
                    Text("\(p.upNext.count) up next")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 4)
            QueueList()
        }
        .frame(width: 380, height: 540)
    }
}

struct QueueList: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.player
        if p.queue.isEmpty {
            ContentUnavailableView("Queue is empty", systemImage: "list.bullet",
                                   description: Text("Songs you play will show up here."))
                .frame(maxHeight: .infinity)
        } else {
            List {
                if let cur = p.current {
                    Section("Now Playing") {
                        QueueRow(item: cur, isCurrent: true)
                    }
                }
                if !p.upNext.isEmpty {
                Section {
                    ForEach(Array(p.upNext.enumerated()), id: \.element.id) { offset, item in
                        QueueRow(item: item, isCurrent: false)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { p.jump(to: p.index + 1 + offset) }
                            .contextMenu {
                                Button("Play Now", systemImage: "play.fill") { p.jump(to: p.index + 1 + offset) }
                                Button("Remove from Queue", systemImage: "minus.circle", role: .destructive) {
                                    p.remove(at: IndexSet(integer: p.index + 1 + offset))
                                }
                                Divider()
                                ItemMenu(item: item)
                            }
                    }
                    .onMove { from, to in
                        let base = p.index + 1
                        p.move(from: IndexSet(from.map { $0 + base }), to: to + base)
                    }
                    .onDelete { offsets in
                        p.remove(at: IndexSet(offsets.map { $0 + p.index + 1 }))
                    }
                } header: {
                    HStack {
                        Text(p.sourceTitle.map { "Next · \($0)" } ?? "Next Up").lineLimit(1)
                        Spacer()
                        if !p.upNext.isEmpty {
                            Button("Clear") { withAnimation { p.clearUpNext() } }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                }
                Section {
                    Toggle(isOn: Binding(get: { p.autoplay }, set: { p.autoplay = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Autoplay").font(.system(size: 13, weight: .semibold))
                            Text("Keep playing similar music when the queue ends")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.sidebar)
        }
    }
}

struct QueueRow: View {
    @Environment(AppModel.self) private var app
    let item: MediaItem
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ArtworkView(artwork: item.artwork, size: 96, cornerRadius: 5).frame(width: 40, height: 40)
                if isCurrent {
                    RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.4)).frame(width: 40, height: 40)
                    EqualizerBars(animating: app.player.isPlaying, color: .white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)
                    .lineLimit(1)
                Text(item.artistLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let d = item.duration {
                Text(d).font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LyricsView: View {
    @Environment(AppModel.self) private var app
    var fontSize: CGFloat = 19

    var body: some View {
        let p = app.player
        Group {
            switch p.lyrics {
            case .loaded(let l):
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(l.text)
                            .font(.system(size: fontSize, weight: .bold))
                            .lineSpacing(fontSize * 0.45)
                            .textSelection(.enabled)
                        if let s = l.source {
                            Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView("No lyrics", systemImage: "quote.bubble",
                                       description: Text("Lyrics aren’t available for this song."))
                    .frame(maxHeight: .infinity)
            case .idle:
                if p.current == nil {
                    ContentUnavailableView("Nothing playing", systemImage: "music.note")
                        .frame(maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { p.wantsLyrics = true }
        .onDisappear { p.wantsLyrics = false }
        .onChange(of: p.current?.videoId) { p.loadLyricsIfNeeded() }
    }
}

struct RelatedView: View {
    @Environment(AppModel.self) private var app
    @State private var page: BrowsePage?
    @State private var loadedId: String?

    var body: some View {
        let rid = app.player.relatedBrowseId
        Group {
            if let page {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(page.shelves.filter { $0.style != .description }) { shelf in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shelf.title).font(.system(size: 15, weight: .bold)).padding(.horizontal, 10)
                                ForEach(shelf.items.prefix(8)) { CompactItemRow(item: $0, width: nil) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)
                }
            } else if app.player.current == nil {
                ContentUnavailableView("Nothing playing", systemImage: "music.note").frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: rid) {
            guard let rid, rid != loadedId else { return }
            page = nil
            page = try? await app.client.browse(rid)
            loadedId = rid
        }
    }
}
