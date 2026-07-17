import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

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
        }
    }
}
