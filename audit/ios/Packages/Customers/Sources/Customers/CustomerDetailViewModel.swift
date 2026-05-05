import Foundation
import Observation
import Core
import Networking

/// Bundles the four parallel-fetched sections. Each nil means the section
/// either hasn't loaded yet or failed silently (same pattern as Android —
/// sections just don't render when their data is missing).
public struct CustomerSnapshot: Sendable {
    public var detail: CustomerDetail?
    public var analytics: CustomerAnalytics?
    public var recentTickets: [TicketSummary]?
    public var recentInvoices: [Networking.InvoiceSummary]?
    public var notes: [CustomerNote]?
}

@MainActor
@Observable
public final class CustomerDetailViewModel {
    public private(set) var snapshot: CustomerSnapshot = .init()
    public private(set) var isLoading: Bool = true
    public private(set) var errorMessage: String?
    public let customerId: Int64

    @ObservationIgnored private let repo: CustomerDetailRepository

    public init(repo: CustomerDetailRepository, customerId: Int64) {
        self.repo = repo
        self.customerId = customerId
    }

    public func load() async {
        if snapshot.detail == nil { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil

        // Primary fetch — fail the screen if we can't even load the core detail.
        do {
            snapshot.detail = try await repo.detail(id: customerId)
        } catch {
            AppLog.ui.error("Customer detail load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }

        // Secondary fetches — silent-degrade, mirror Android fire-and-forget.
        async let analytics = try? repo.analytics(id: customerId)
        async let tickets = try? repo.recentTickets(id: customerId)
        async let invoices = try? repo.recentInvoices(id: customerId)
        async let notes = try? repo.notes(id: customerId)

        snapshot.analytics = await analytics
        snapshot.recentTickets = await tickets
        snapshot.recentInvoices = await invoices
        snapshot.notes = await notes
    }
}

public protocol CustomerDetailRepository: Sendable {
    func detail(id: Int64) async throws -> CustomerDetail
    func analytics(id: Int64) async throws -> CustomerAnalytics
    func recentTickets(id: Int64) async throws -> [TicketSummary]
    func recentInvoices(id: Int64) async throws -> [Networking.InvoiceSummary]
    func notes(id: Int64) async throws -> [CustomerNote]
}

public actor CustomerDetailRepositoryImpl: CustomerDetailRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func detail(id: Int64) async throws -> CustomerDetail {
        try await api.customer(id: id)
    }
    public func analytics(id: Int64) async throws -> CustomerAnalytics {
        try await api.customerAnalytics(id: id)
    }
    public func recentTickets(id: Int64) async throws -> [TicketSummary] {
        try await api.customerRecentTickets(id: id)
    }
    public func recentInvoices(id: Int64) async throws -> [Networking.InvoiceSummary] {
        try await api.customerRecentInvoices(id: id)
    }
    public func notes(id: Int64) async throws -> [CustomerNote] {
        try await api.customerNotes(id: id)
    }
}
