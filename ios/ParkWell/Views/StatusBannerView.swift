import SwiftUI

/// The big glanceable status card — same color language as the Live Activity.
struct StatusBannerView: View {
    let verdict: Verdict?

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 88, height: 88)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            Text(verdict?.headline ?? "Waiting for location…")
                .font(.title2.bold())
            Text(verdict?.detail ?? "Drive into a mapped zone to see live status")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch verdict?.level {
        case .green: return .green
        case .likelyFree: return .green.opacity(0.55)
        case .yellow: return .yellow
        case .red: return .red
        case .unknown, nil: return .gray
        }
    }

    private var symbol: String {
        switch verdict?.level {
        case .green: return "checkmark"
        case .likelyFree: return "checkmark"
        case .yellow: return "dollarsign"
        case .red: return "xmark"
        case .unknown, nil: return "questionmark"
        }
    }
}
