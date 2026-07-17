import ActivityKit
import Foundation

/// Starts, updates, and ends the ParkWell Live Activity. Updates are local
/// (the app is running while driving), so no push token plumbing is needed
/// for Phase 1.
final class LiveActivityController {
    private var activity: Activity<ParkingActivityAttributes>?

    var isActive: Bool { activity != nil }

    func start(with verdict: Verdict) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            update(with: verdict)
            return
        }
        let attributes = ParkingActivityAttributes(cityName: "Halifax")
        let state = contentState(from: verdict)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: Date().addingTimeInterval(120))
        )
    }

    func update(with verdict: Verdict) {
        guard let activity else { return }
        let state = contentState(from: verdict)
        Task {
            // staleDate makes iOS visually mark the surface out-of-date if we
            // stop updating (tunnel, GPS loss) — honest degradation for free.
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(120)))
        }
    }

    func end() {
        guard let activity else { return }
        let finalState = ParkingActivityAttributes.ContentState(
            level: .unknown, headline: "Drive ended", detail: "", isStale: false, updatedAt: Date()
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }

    private func contentState(from verdict: Verdict) -> ParkingActivityAttributes.ContentState {
        .init(
            level: verdict.level,
            headline: verdict.headline,
            detail: verdict.detail,
            isStale: verdict.isStale,
            updatedAt: Date()
        )
    }
}
