import ActivityKit
import SwiftUI
import WidgetKit

/// The glanceable surface: one color, one word, readable in a half-second
/// glance at the Dynamic Island or Lock Screen while driving.
struct ParkingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ParkingActivityAttributes.self) { context in
            // Lock Screen / banner
            LockScreenView(state: context.state)
                .activityBackgroundTint(color(for: context.state.level).opacity(0.2))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    statusDot(context.state.level)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.headline)
                            .font(.headline)
                        Text(context.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isStale {
                        Label("Data may be out of date — check signs", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } compactLeading: {
                statusDot(context.state.level)
            } compactTrailing: {
                Text(shortLabel(context.state.level))
                    .font(.caption2.bold())
                    .foregroundStyle(color(for: context.state.level))
            } minimal: {
                statusDot(context.state.level)
            }
        }
    }

    private func statusDot(_ level: StatusLevel) -> some View {
        Circle()
            .fill(color(for: level))
            .frame(width: 18, height: 18)
    }

    private func shortLabel(_ level: StatusLevel) -> String {
        switch level {
        case .green: return "PARK"
        case .likelyFree: return "OK?"
        case .yellow: return "PAID"
        case .red: return "NO"
        case .unknown: return "?"
        }
    }

    private func color(for level: StatusLevel) -> Color {
        switch level {
        case .green: return .green
        case .likelyFree: return .green.opacity(0.55)
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .gray
        }
    }
}

private struct LockScreenView: View {
    let state: ParkingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: symbol)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.headline)
                    .font(.headline)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state.isStale {
                    Label("Data may be out of date", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var color: Color {
        switch state.level {
        case .green: return .green
        case .likelyFree: return .green.opacity(0.55)
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .gray
        }
    }

    private var symbol: String {
        switch state.level {
        case .green: return "checkmark"
        case .likelyFree: return "checkmark"
        case .yellow: return "dollarsign"
        case .red: return "xmark"
        case .unknown: return "questionmark"
        }
    }
}
