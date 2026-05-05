import Foundation
import Networking

// MARK: - Request / Response bodies

public struct WaitlistCreateBody: Encodable, Sendable {
    public let customerId: Int64
    public let requestedServiceType: String
    public let preferredWindows: [PreferredWindow]
    public let note: String?

    public init(
        customerId: Int64,
        requestedServiceType: String,
        preferredWindows: [PreferredWindow],
        note: String? = nil
    ) {
        self.customerId = customerId
        self.requestedServiceType = requestedServiceType
        self.preferredWindows = preferredWindows
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case customerId           = "customer_id"
        case requestedServiceType = "requested_service_type"
        case preferredWindows     = "preferred_windows"
        case note
    }
}

public struct WaitlistListResponse: Decodable, Sendable {
    public let entries: [WaitlistEntry]
    public init(entries: [WaitlistEntry]) { self.entries = entries }
}

/// Empty body for action endpoints (POST with no payload).
private struct EmptyBody: Encodable, Sendable {
    init() {}
}

// MARK: - APIClient extension

public extension APIClient {
    // POST /waitlist
    func createWaitlistEntry(_ body: WaitlistCreateBody) async throws -> WaitlistEntry {
        try await post("/api/v1/waitlist", body: body, as: WaitlistEntry.self)
    }

    // GET /waitlist
    func listWaitlistEntries() async throws -> [WaitlistEntry] {
        try await get("/api/v1/waitlist", as: WaitlistListResponse.self).entries
    }

    // POST /waitlist/:id/offer
    func offerWaitlistEntry(id: String) async throws -> WaitlistEntry {
        try await post("/api/v1/waitlist/\(id)/offer", body: EmptyBody(), as: WaitlistEntry.self)
    }

    // POST /waitlist/:id/cancel
    func cancelWaitlistEntry(id: String) async throws -> WaitlistEntry {
        try await post("/api/v1/waitlist/\(id)/cancel", body: EmptyBody(), as: WaitlistEntry.self)
    }
}
