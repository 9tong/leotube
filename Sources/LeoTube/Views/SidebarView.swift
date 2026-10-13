import SwiftUI
import YTMusicKit

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selection) {
            Section {
                Label("Home", systemImage: "house.fill").tag(SidebarItem.home)
                Label("Explore", systemImage: "safari.fill").tag(SidebarItem.explore)
                Label("Search", systemImage: "magnifyingglass").tag(SidebarItem.search)
                Label("Library", systemImage: "square.stack.fill").tag(SidebarItem.library)
            }

            if app.auth.isSignedIn {
                Section("Your Music") {
                    SidebarCollectionRow(title: "Liked Music", subtitle: "Auto playlist", symbol: "heart.fill")
                        .tag(SidebarItem.collection(BrowseTarget(browseId: "VLLM"), title: "Liked Music"))
                }
                Section {
                    ForEach(app.libraryPlaylists.filter { $0.browse?.browseId != "VLLM" }) { p in
                        if let b = p.browse {
                            SidebarPlaylistRow(item: p)
                                .tag(SidebarItem.collection(b, title: p.title))
                                .contextMenu { ItemMenu(item: p) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Playlists")
                        Spacer()
                        Button {
                            app.beginNewPlaylist()
                        } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("New Playlist")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AccountBadge()
                .padding(10)
        }
    }
}

private struct SidebarCollectionRow: View {
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct SidebarPlaylistRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(artwork: item.artwork, size: 80, cornerRadius: 6)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }
}

struct AccountBadge: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if app.auth.isSignedIn {
            Menu {
                if let handle = app.auth.account?.handle { Text(handle) }
                Button("Settings…", systemImage: "gearshape") { openSettings() }
                Button("Open YouTube Music in Browser", systemImage: "safari") {
                    NSWorkspace.shared.open(URL(string: "https://music.youtube.com")!)
                }
                Divider()
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await app.signOut() }
                }
            } label: {
                HStack(spacing: 10) {
                    ArtworkView(artwork: app.auth.account?.avatar, size: 96, circle: true, placeholderSymbol: "person.fill")
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.auth.account?.name ?? "Signed in")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(app.auth.account?.handle ?? "YouTube Music")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Button {
                app.showLogin = true
            } label: {
                Label("Sign In", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentCapsuleStyle(height: 38))
        }
    }
}
