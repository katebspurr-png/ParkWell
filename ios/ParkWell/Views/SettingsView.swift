import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingWelcome = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio cue") {
                    Picker("When entering a new zone", selection: $model.cueStyleRaw) {
                        ForEach(AudioCueService.CueStyle.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Text("Cues duck your music or podcast briefly — they never pause it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Parking suggestions") {
                    Picker("When you can't park here, suggest", selection: $model.preferenceRaw) {
                        ForEach(ParkingPreference.allCases) { preference in
                            Text(preference.label).tag(preference.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Text("Free only sticks to streets with no charge. Cheapest first ranks paid streets by zone rate; lots and garages come last. Nearest is pure distance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("CarPlay") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("See your parking status on the car screen")
                        Text("Settings → General → CarPlay → your car → Live Activities")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Show welcome tips again") {
                        showingWelcome = true
                    }
                }

                Section("Coverage") {
                    LabeledContent("City", value: "Halifax / Dartmouth")
                    LabeledContent("Zones", value: "B, C, H")
                }

                Section {
                    Text("ParkWell reads your location only to show parking rules for the street you're on. Location is processed on-device and never stored on our servers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
            .sheet(isPresented: $showingWelcome) {
                WelcomeView()
            }
        }
    }
}
