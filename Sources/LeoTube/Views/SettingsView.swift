import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section("Account") {
                if app.auth.isSignedIn {
                    HStack(spacing: 12) {
                        ArtworkView(artwork: app.auth.account?.avatar, size: 96, circle: true, placeholderSymbol: "person.fill")
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading) {
                            Text(app.auth.account?.name ?? "Signed in").font(.headline)
                            if let h = app.auth.account?.handle { Text(h).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
                    }
                } else {
                    HStack {
                        Text("Not signed in")
                        Spacer()
                        Button("Sign In…") { app.showLogin = true }
                    }
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $app.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                TextField("Language (hl)", text: $app.contentLanguage)
                TextField("Region (gl)", text: $app.contentRegion)
            } header: {
                Text("Content")
            } footer: {
                Text("Controls the language and country of recommendations, charts and titles, e.g. “en” / “US”, “zh-CN” / “CN”, “ja” / “JP”.")
            }
            Section("Playback") {
                Toggle("Autoplay similar music when the queue ends", isOn: Binding(
                    get: { app.player.autoplay }, set: { app.player.autoplay = $0 }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
