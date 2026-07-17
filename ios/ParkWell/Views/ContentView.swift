import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false
    @State private var showingScanner = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                StatusBannerView(verdict: model.verdict)

                if model.verdict?.isStale == true {
                    Label("Rule data hasn't refreshed recently — trust the posted signs.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }

                Spacer()

                Button {
                    model.isDriving ? model.endDrive() : model.startDrive()
                } label: {
                    Label(model.isDriving ? "End drive" : "Start drive",
                          systemImage: model.isDriving ? "stop.circle.fill" : "car.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isDriving ? .red : .accentColor)

                Button {
                    showingScanner = true
                } label: {
                    Label("Scan a confusing sign", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Text("Posted signs always win. GPS can be off by a lane — ParkWell can't guarantee against a ticket.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("ParkWell")
            .toolbar {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .onAppear {
                if !hasSeenWelcome {
                    showingWelcome = true
                    hasSeenWelcome = true
                }
            }
            .sheet(isPresented: $showingWelcome) {
                WelcomeView()
            }
            .sheet(isPresented: $showingScanner) {
                SignScannerView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(model)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
