import SwiftUI

/// First-launch welcome sheet. Reopenable from Settings.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 6) {
                        Text("Welcome to ParkWell")
                            .font(.largeTitle.bold())
                        Text("Can I park here, right now? Answered before you have to ask.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    row(icon: "circle.fill", tint: .green,
                        title: "Glanceable status",
                        text: "While you drive, the street you're passing shows green (park), yellow (paid or limited), or red (don't) — on your Lock Screen and in the Dynamic Island.")

                    row(icon: "speaker.wave.2.fill", tint: .blue,
                        title: "Spoken cues",
                        text: "When the rules change under you, ParkWell says so — briefly ducking your music, never pausing it.")

                    row(icon: "camera.viewfinder", tint: .purple,
                        title: "Confusing sign?",
                        text: "Snap a photo and get a plain-English answer for right now.")

                    carPlayTip

                    Text("Posted signs always win. GPS can be off by a lane — ParkWell can't guarantee against a ticket.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        dismiss()
                    } label: {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
            }
            .interactiveDismissDisabled(false)
        }
    }

    /// The CarPlay Live Activities toggle is buried and off some users'
    /// radar entirely — surface it up front since the dash status is one of
    /// the best parts of the app.
    private var carPlayTip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Got CarPlay?", systemImage: "car.fill")
                .font(.headline)
            Text("Your parking status can appear right on your car's screen. If it doesn't show up automatically, turn it on here:")
                .font(.subheadline)
            Text("Settings → General → CarPlay → *your car* → **Live Activities**")
                .font(.subheadline.weight(.medium))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text("Audio cues already play through your car's speakers — no setup needed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(icon: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView()
}
