import Foundation

/// Fetches the static layer (segments + rules) and dynamic overlay layer
/// (winter ban, street cleaning) from Supabase, with a local cache so the app
/// works offline — honestly flagged as stale via `DynamicOverlays.fetchedAt`.
///
/// Uses plain PostgREST endpoints over URLSession; no SDK dependency needed
/// for three read-only queries.
actor RulesRepository {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    private(set) var segments: [StreetSegment] = []
    private(set) var payStations: [PayStation] = []
    private(set) var overlays: DynamicOverlays?

    init(baseURL: URL = Config.supabaseURL, anonKey: String = Config.supabaseAnonKey, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Loads cache immediately (so a verdict is available before the network
    /// answers), then refreshes from the backend.
    func load() async {
        loadFromCache()
        await refresh()
    }

    func refresh() async {
        async let fetchedSegments = fetchSegments()
        async let fetchedStations = fetchPayStations()
        async let fetchedOverlays = fetchOverlays()
        if let s = try? await fetchedSegments { segments = s }
        if let p = try? await fetchedStations { payStations = p }
        if let o = try? await fetchedOverlays { overlays = o }
        saveToCache()
    }

    // MARK: - Network

    private func fetchSegments() async throws -> [StreetSegment] {
        let rows: [SegmentRow] = try await get("street_segments", query: "select=*,segment_rules(*)")
        return rows.map { $0.toModel() }
    }

    private func fetchPayStations() async throws -> [PayStation] {
        let rows: [PayStationRow] = try await get("pay_stations", query: "select=*")
        return rows.map { $0.toModel() }
    }

    private func fetchOverlays() async throws -> DynamicOverlays {
        async let banRows: [WinterBanRow] = get("winter_ban_status", query: "select=*&id=eq.1")
        async let cleaningRows: [StreetCleaningRow] = get("street_cleaning", query: "select=*")
        let ban = try await banRows.first
        let cleaning = try await cleaningRows
        return DynamicOverlays(
            winterBanActive: ban?.active ?? false,
            winterBanMessage: ban?.message,
            streetCleaning: cleaning.map { $0.toModel() },
            fetchedAt: Date()
        )
    }

    private func get<T: Decodable>(_ table: String, query: String) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: "/rest/v1/\(table)")
            .appending(queryItems: URLQueryItem.parse(query)))
        // Publishable (sb_publishable_...) keys go in the apikey header only —
        // they are not JWTs and must not be sent as a Bearer token.
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(string)"))
        }
        return decoder
    }()

    // MARK: - Cache

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "rules-cache.json")
    }

    private struct CachePayload: Codable {
        var segments: [StreetSegment]
        var payStations: [PayStation]?
        var overlays: DynamicOverlays?
    }

    private func loadFromCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else { return }
        segments = payload.segments
        payStations = payload.payStations ?? []
        overlays = payload.overlays  // fetchedAt survives, so staleness stays honest
    }

    private func saveToCache() {
        let payload = CachePayload(segments: segments, payStations: payStations, overlays: overlays)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

// MARK: - Row DTOs (snake_case DB rows → domain models)

private struct SegmentRow: Decodable {
    struct RuleRow: Decodable {
        var id: UUID
        var kind: String
        var windows: [WindowRow]?
        var timeLimitMinutes: Int?
        var note: String?
    }
    struct WindowRow: Decodable {
        var weekdays: [Int]
        var startMinute: Int
        var endMinute: Int
        var effectiveFrom: Date?
        var effectiveUntil: Date?
    }

    var id: UUID
    var zoneCode: String?
    var streetName: String
    var side: String
    var polyline: [[Double]]  // [[lat, lon], ...]
    var segmentRules: [RuleRow]?

    func toModel() -> StreetSegment {
        StreetSegment(
            id: id,
            zoneCode: zoneCode,
            streetName: streetName,
            side: side,
            polyline: polyline.compactMap { pair in
                pair.count == 2 ? Coordinate(latitude: pair[0], longitude: pair[1]) : nil
            },
            rules: (segmentRules ?? []).map { row in
                ParkingRule(
                    id: row.id,
                    kind: RuleKind(rawValue: row.kind) ?? .free,
                    windows: (row.windows ?? []).map {
                        TimeWindow(weekdays: Set($0.weekdays), startMinute: $0.startMinute,
                                   endMinute: $0.endMinute, effectiveFrom: $0.effectiveFrom,
                                   effectiveUntil: $0.effectiveUntil)
                    },
                    timeLimitMinutes: row.timeLimitMinutes,
                    note: row.note
                )
            }
        )
    }
}

private struct PayStationRow: Decodable {
    var id: UUID
    var tid: String
    var zoneCode: String?
    var street: String?
    var latitude: Double
    var longitude: Double

    func toModel() -> PayStation {
        PayStation(id: id, tid: tid, zoneCode: zoneCode, street: street,
                   latitude: latitude, longitude: longitude)
    }
}

private struct WinterBanRow: Decodable {
    var active: Bool
    var message: String?
}

private struct StreetCleaningRow: Decodable {
    var segmentId: UUID
    var weekday: Int
    var startMinute: Int
    var endMinute: Int

    func toModel() -> StreetCleaningEntry {
        StreetCleaningEntry(segmentID: segmentId, weekday: weekday,
                            startMinute: startMinute, endMinute: endMinute)
    }
}

private extension URLQueryItem {
    static func parse(_ query: String) -> [URLQueryItem] {
        query.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            return URLQueryItem(name: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : nil)
        }
    }
}
