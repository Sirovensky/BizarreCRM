import Foundation
import Networking

// MARK: - OwnerPLRepository
//
// Wired to GET /api/v1/owner-pl/summary (ownerPl.routes.ts, admin-only).
// Envelope: { success: Bool, data: OwnerPLSummary }

public protocol OwnerPLRepository: Sendable {
    func getSummary(from: String, to: String, rollup: OwnerPLRollup) async throws -> OwnerPLSummary
}

// MARK: - OwnerPLRollup

public enum OwnerPLRollup: String, CaseIterable, Sendable, Identifiable {
    case day   = "day"
    case week  = "week"
    case month = "month"

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        }
    }
}

// MARK: - LiveOwnerPLRepository

public actor LiveOwnerPLRepository: OwnerPLRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func getSummary(
        from: String,
        to: String,
        rollup: OwnerPLRollup = .day
    ) async throws -> OwnerPLSummary {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from",   value: from),
            URLQueryItem(name: "to",     value: to),
            URLQueryItem(name: "rollup", value: rollup.rawValue)
        ]
        return try await api.get("/api/v1/owner-pl/summary", query: query, as: OwnerPLSummary.self)
    }
}
