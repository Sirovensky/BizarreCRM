/// GatePreviewHelpers.swift
/// Agent B — Customer Gate (Frame 1)
///
/// Lightweight in-memory stubs for SwiftUI previews and unit tests.
/// Intentionally minimal — only covers the surface area the Gate needs.

#if DEBUG
import Foundation
import Customers
import Networking

// MARK: - Preview CustomerRepository

/// Returns a fixed list of CustomerSummary values for preview / test use.
public struct PreviewCustomerRepository: CustomerRepository {
    private let summaries: [CustomerSummary]

    public init(summaries: [CustomerSummary] = Self.sampleData) {
        self.summaries = summaries
    }

    public func list(keyword: String?) async throws -> [CustomerSummary] {
        guard let keyword, !keyword.isEmpty else { return summaries }
        return summaries.filter { $0.displayName.localizedCaseInsensitiveContains(keyword) }
    }

    public func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        throw URLError(.unsupportedURL) // not needed in gate previews
    }

    static let sampleData: [CustomerSummary] = [
        CustomerSummary(
            id: 1, firstName: "Sarah", lastName: "Mullen",
            email: "sarah@example.com", phone: "555-1234", mobile: nil,
            organization: nil, city: "Austin", state: "TX",
            customerGroupName: nil, createdAt: nil, ticketCount: 3
        ),
        CustomerSummary(
            id: 2, firstName: "Marco", lastName: "Diaz",
            email: nil, phone: "555-5678", mobile: "555-5678",
            organization: nil, city: nil, state: nil,
            customerGroupName: nil, createdAt: nil, ticketCount: 1
        ),
    ]
}

// MARK: - Failing CustomerRepository

/// Throws every call — used to test error surfaces.
public struct FailingCustomerRepository: CustomerRepository {
    public let error: Error

    public init(error: Error = URLError(.notConnectedToInternet)) {
        self.error = error
    }

    public func list(keyword: String?) async throws -> [CustomerSummary] {
        throw error
    }

    public func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        throw error
    }
}

// MARK: - Preview GateTicketsRepository

public struct PreviewGateTicketsRepository: GateTicketsRepository {
    private let pickups: [ReadyPickup]

    public init(pickups: [ReadyPickup] = []) {
        self.pickups = pickups
    }

    public func readyForPickup(limit: Int) async throws -> [ReadyPickup] {
        return Array(pickups.prefix(limit))
    }
}

// MARK: - Failing GateTicketsRepository

public struct FailingGateTicketsRepository: GateTicketsRepository {
    public let error: Error

    public init(error: Error = URLError(.notConnectedToInternet)) {
        self.error = error
    }

    public func readyForPickup(limit: Int) async throws -> [ReadyPickup] {
        throw error
    }
}

// MARK: - CustomerSummary init for testing

// CustomerSummary lacks a public memberwise init because its CodingKeys remaps
// all property names. This extension provides a convenience init for tests.
extension CustomerSummary {
    init(
        id: Int64,
        firstName: String?,
        lastName: String?,
        email: String?,
        phone: String?,
        mobile: String?,
        organization: String?,
        city: String?,
        state: String?,
        customerGroupName: String?,
        createdAt: String?,
        ticketCount: Int?
    ) {
        // Decode from a dictionary so we stay inside the public API.
        // This is test-only code — force try is acceptable here.
        let dict: [String: Any?] = [
            "id": id,
            "first_name": firstName,
            "last_name": lastName,
            "email": email,
            "phone": phone,
            "mobile": mobile,
            "organization": organization,
            "city": city,
            "state": state,
            "customer_group_name": customerGroupName,
            "created_at": createdAt,
            "ticket_count": ticketCount
        ]
        let filtered = dict.compactMapValues { $0 }
        let data = try! JSONSerialization.data(withJSONObject: filtered)
        self = try! JSONDecoder().decode(CustomerSummary.self, from: data)
    }
}
#endif
