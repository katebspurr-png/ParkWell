import Foundation

/// Where the driver would rather be pointed when the current street is a no.
enum ParkingPreference: String, CaseIterable, Identifiable {
    /// Only green/likelyFree streets — never paid streets or garages.
    case freeOnly = "free_only"
    /// Free streets, then paid streets by ascending zone rate (unknown rates
    /// after known ones), then garages/lots last. The default.
    case cheapestFirst = "cheapest_first"
    /// Pure distance across streets and garages alike.
    case nearest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .freeOnly: return "Free only"
        case .cheapestFirst: return "Cheapest first"
        case .nearest: return "Nearest"
        }
    }

    var allowsGarages: Bool { self != .freeOnly }
}

/// Pure ranking of candidate parking options by the user's preference.
/// No I/O, no clocks — callers resolve verdicts and distances first, so this
/// is fully unit-testable.
struct SuggestionEngine {
    struct StreetCandidate: Equatable {
        var name: String
        var meters: Double
        /// green/likelyFree. False means an active paid street.
        var isFree: Bool
        /// Current zone rate for paid candidates; nil = unknown-but-paid.
        var hourlyRateCents: Int?
    }

    struct GarageCandidate: Equatable {
        var name: String
        var meters: Double
    }

    enum Suggestion: Equatable {
        case street(name: String, meters: Double, isFree: Bool, hourlyRateCents: Int?)
        case garage(name: String, meters: Double)

        var meters: Double {
            switch self {
            case .street(_, let meters, _, _), .garage(_, let meters): return meters
            }
        }
    }

    func best(streets: [StreetCandidate], garages: [GarageCandidate],
              mode: ParkingPreference) -> Suggestion? {
        let free = streets.filter(\.isFree)
        let paid = streets.filter { !$0.isFree }
        let nearestGarage = garages.min { $0.meters < $1.meters }

        switch mode {
        case .freeOnly:
            return free.min { $0.meters < $1.meters }.map(Self.suggestion)

        case .cheapestFirst:
            if let street = free.min(by: { $0.meters < $1.meters }) {
                return Self.suggestion(street)
            }
            // Known rates rank by (rate, distance); unknown rates are
            // conservatively assumed pricier than any known street.
            let known = paid.filter { $0.hourlyRateCents != nil }
            if let street = known.min(by: {
                ($0.hourlyRateCents ?? .max, $0.meters) < ($1.hourlyRateCents ?? .max, $1.meters)
            }) {
                return Self.suggestion(street)
            }
            if let street = paid.min(by: { $0.meters < $1.meters }) {
                return Self.suggestion(street)
            }
            // Garages have no pricing data yet — assume priciest, so last.
            return nearestGarage.map { .garage(name: $0.name, meters: $0.meters) }

        case .nearest:
            let street = streets.min { $0.meters < $1.meters }
            switch (street, nearestGarage) {
            case (let s?, let g?):
                return s.meters <= g.meters ? Self.suggestion(s) : .garage(name: g.name, meters: g.meters)
            case (let s?, nil):
                return Self.suggestion(s)
            case (nil, let g?):
                return .garage(name: g.name, meters: g.meters)
            case (nil, nil):
                return nil
            }
        }
    }

    private static func suggestion(_ street: StreetCandidate) -> Suggestion {
        .street(name: street.name, meters: street.meters,
                isFree: street.isFree, hourlyRateCents: street.hourlyRateCents)
    }
}
