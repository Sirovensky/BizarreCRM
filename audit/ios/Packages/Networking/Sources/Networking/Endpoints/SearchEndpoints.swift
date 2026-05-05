import Foundation

/// `GET /api/v1/search?q=...` — grouped by entity type.
/// Server: packages/server/src/routes/search.routes.ts:38,131.
public struct GlobalSearchResults: Decodable, Sendable {
    public let customers: [Row]
    public let tickets: [Row]
    public let inventory: [Row]
    public let invoices: [Row]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customers = (try? c.decode([Row].self, forKey: .customers)) ?? []
        tickets = (try? c.decode([Row].self, forKey: .tickets)) ?? []
        inventory = (try? c.decode([Row].self, forKey: .inventory)) ?? []
        invoices = (try? c.decode([Row].self, forKey: .invoices)) ?? []
    }

    public var isEmpty: Bool {
        customers.isEmpty && tickets.isEmpty && inventory.isEmpty && invoices.isEmpty
    }

    public struct Row: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let display: String?
        public let type: String?
        public let subtitle: String?

        /// Memberwise init for constructing rows in tests and merge logic.
        public init(id: Int64, display: String?, type: String?, subtitle: String?) {
            self.id = id
            self.display = display
            self.type = type
            self.subtitle = subtitle
        }
    }

    /// Memberwise init for constructing synthetic results in tests and merge logic.
    public init(
        customers: [Row],
        tickets: [Row],
        inventory: [Row],
        invoices: [Row]
    ) {
        self.customers = customers
        self.tickets = tickets
        self.inventory = inventory
        self.invoices = invoices
    }

    enum CodingKeys: String, CodingKey { case customers, tickets, inventory, invoices }
}

public extension APIClient {
    func globalSearch(_ query: String) async throws -> GlobalSearchResults {
        try await get("/api/v1/search",
                      query: [URLQueryItem(name: "q", value: query)],
                      as: GlobalSearchResults.self)
    }
}
