import SwiftUI

/// First-launch welcome screen.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @State private var phase = false

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.18 * sin(t * 0.5)), Float(0.5 + 0.15 * cos(t * 0.4))], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Color(red: 0.12, green: 0.02, blue: 0.08), Color(red: 0.45, green: 0.04, blue: 0.16), Color(red: 0.1, green: 0.03, blue: 0.2),
                    Color(red: 0.55, green: 0.05, blue: 0.2), Color(red: 1.0, green: 0.2, blue: 0.32), Color(red: 0.4, green: 0.1, blue: 0.45),
                    Color(red: 0.08, green: 0.02, blue: 0.1), Color(red: 0.6, green: 0.2, blue: 0.1), Color(red: 0.05, green: 0.02, blue: 0.12),
                ])
            }
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 148, height: 148)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 30, y: 12)
                .scaleEffect(phase ? 1 : 0.8)
                .opacity(phase ? 1 : 0)

                VStack(spacing: 10) {
                    Text("LeoTube")
                        .font(.system(size: 54, weight: .black))
                        .tracking(-1.5)
                    Text("YouTube Music, beautifully native on your Mac.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .offset(y: phase ? 0 : 16)
                .opacity(phase ? 1 : 0)

                HStack(spacing: 22) {
                    feature("sparkles", "Made for you", "Your mixes, Albums for You and daily picks")
                    feature("crown", "Premium aware", "Ad-free, high quality with your subscription")
                    feature("keyboard", "Truly native", "Media keys, Control Center and Liquid Glass")
                }
                .padding(.top, 8)
                .opacity(phase ? 1 : 0)

                VStack(spacing: 12) {
                    Button {
                        app.showLogin = true
                    } label: {
                        Label("Sign in with Google", systemImage: "person.crop.circle.fill")
                            .frame(width: 240)
                    }
                    .buttonStyle(AccentCapsuleStyle(height: 46))

                    Button {
                        withAnimation(.easeOut(duration: 0.35)) { app.continueAsGuest() }
                    } label: {
                        Text("Continue without signing in")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 280, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.9))
                    .glassEffect(.clear.interactive(), in: Capsule())
                }
                .padding(.top, 10)
                .opacity(phase ? 1 : 0)
                Spacer()
                Text("Not affiliated with Google or YouTube.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 18)
            }
            .padding(40)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.1)) { phase = true } }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 200, height: 118, alignment: .topLeading)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
