/// PosGateViewModel.swift
/// Agent B — Customer Gate (Frame 1)
///
/// @MainActor @Observable VM for the customer gate screen.
/// Drives search, debounce, cancellation, and ready-for-pickup strip.

#if canImport(UIKit)
import Foundation
import Observation
import Networking
import Customers
import Core

// MARK: - Supporting types

/// Lightweight result row for search hits.
public struct CustomerSearchHit: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let displayName: String
    public let contactLine: String?
    public let initials: String

    public init(id: Int64, displayName: String, contactLine: String?, initials: String) {
        self.id = id
        self.displayName = displayName
        self.contactLine = contactLine
        self.initials = initials
    }

    init(summary: CustomerSummary) {
        self.id = summary.id
        self.displayName = summary.displayName
        self.contactLine = summary.contactLine
        self.initials = summary.initials
    }
}

/// A ticket that is ready for customer pickup.
public struct ReadyPickup: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let orderId: String
    public let customerName: String
    public let deviceSummary: String?
    /// Total in cents.
    public let totalCents: Int

    public var totalFormatted: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.0f", dollars)
    }

    public init(id: Int64, orderId: String, customerName: String, deviceSummary: String?, totalCents: Int) {
        self.id = id
        self.orderId = orderId
        self.customerName = customerName
        self.deviceSummary = deviceSummary
        self.totalCents = totalCents
    }
}

// MARK: - Protocol for injectable TicketsRepository

/// Minimal tickets surface needed by the gate. Extracted so tests can provide a
/// stand-alone mock without pulling in the full Tickets package (which is not a
/// Pos dependency).
public protocol GateTicketsRepository: Sendable {
    /// Return tickets filtered to a ready-for-pickup status group.
    /// Implementation should query `status_group=on_hold` + local filter by
    /// status name keywords, OR a dedicated endpoint if one is added in future.
    func readyForPickup(limit: Int) async throws -> [ReadyPickup]
}

// MARK: - APIClient-backed implementation

/// Production implementation that reads from the tickets API.
/// The server does NOT have a dedicated `?status=ready_for_pickup` query param —
/// the closest match is `status_group=on_hold` which captures waiting/hold states.
/// We then filter client-side for statuses whose name contains pickup keywords.
///
/// TODO: Ask backend to add `GET /api/v1/tickets?status_group=ready_for_pickup`
/// so this doesn't need a client-side post-filter. Track in SCAN ticket.
public actor DefaultGateTicketsRepository: GateTicketsRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func readyForPickup(limit: Int) async throws -> [ReadyPickup] {
        // Use status_group=on_hold as the broadest "waiting" bucket and then
        // filter by status name locally.
        let items = [
            URLQueryItem(name: "status_group", value: "on_hold"),
            URLQueryItem(name: "pagesize", value: String(limit * 3)) // over-fetch then trim
        ]
        let response = try await api.get(
            "/api/v1/tickets",
            query: items,
            as: TicketsListResponse.self
        )
        let pickupKeywords = ["ready for pickup", "ready for collection", "awaiting pickup", "pickup"]
        let filtered = response.tickets.filter { ticket in
            guard let statusName = ticket.status?.name.lowercased() else { return false }
            return pickupKeywords.contains(where: { statusName.contains($0) })
        }
        return Array(filtered.prefix(limit)).map { ticket in
            ReadyPickup(
                id: ticket.id,
                orderId: ticket.orderId,
                customerName: ticket.customer?.displayName ?? "Unknown",
                deviceSummary: {
                    guard let d = ticket.firstDevice else { return nil }
                    let parts = [d.deviceName, d.serviceName].compactMap { $0?.isEmpty == false ? $0 : nil }
                    return parts.joined(separator: " · ")
                }(),
                totalCents: ticket.total
            )
        }
    }
}

// MARK: - View model

@MainActor
@Observable
public final class PosGateViewModel {

    // MARK: Published state

    /// The live search query bound to .searchable.
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            onQueryChange(query)
        }
    }

    /// Search results shown in the list.
    public private(set) var results: [CustomerSearchHit] = []

    /// True while a network search is in flight.
    public private(set) var isSearching: Bool = false

    /// Non-nil when a search or pickup load has failed.
    public private(set) var errorMessage: String?

    /// Up to 2 ready-for-pickup tickets shown in the strip.
    public private(set) var pickupTickets: [ReadyPickup] = []

    /// Total count of ready-for-pickup tickets (may exceed pickupTickets.count).
    public private(set) var totalPickupCount: Int = 0

    /// Whether the full pickup list sheet is presented.
    public var isShowingPickupSheet: Bool = false

    // MARK: Route callback

    /// Called once when the user selects a route exit.
    public var onRouteSelected: (PosGateRoute) -> Void = { _ in }

    // MARK: Private

    private let customerRepo: CustomerRepository
    private let ticketsRepo: GateTicketsRepository
    private var debounceTask: Task<Void, Never>?

    // MARK: Init

    public init(
        customerRepo: CustomerRepository,
        ticketsRepo: GateTicketsRepository
    ) {
        self.customerRepo = customerRepo
        self.ticketsRepo = ticketsRepo
    }

    // MARK: Query change + debounce

    /// Called by the `query` property observer. Cancels any in-flight
    /// debounce task, then schedules a new 250 ms-delayed search.
    func onQueryChange(_ newValue: String) {
        debounceTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            errorMessage = nil
            return
        }
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000) // 250 ms
                guard !Task.isCancelled else { return }
                await self?.performSearch(keyword: trimmed)
            } catch {
                // Task was cancelled — swallow the CancellationError.
            }
        }
    }

    // MARK: Search

    private func performSearch(keyword: String) async {
        isSearching = true
        errorMessage = nil
        do {
            let summaries = try await customerRepo.list(keyword: keyword)
            guard !Task.isCancelled else { return }
            results = summaries.map(CustomerSearchHit.init(summary:))
            AppLog.pos.info("PosGateVM: \(results.count, privacy: .public) results for query")
        } catch {
            guard !Task.isCancelled else { return }
            let msg = error.localizedDescription
            errorMessage = "Search failed: \(msg)"
            AppLog.pos.error("PosGateVM: search error — \(msg, privacy: .public)")
        }
        isSearching = false
    }

    // MARK: Pickup strip

    /// Loads up to 2 ready-for-pickup tickets for the strip.
    /// Call once on appear.
    public func loadPickups() async {
        do {
            // Load a larger set to compute totalPickupCount; show first 2 in strip.
            let all = try await ticketsRepo.readyForPickup(limit: 20)
            pickupTickets = Array(all.prefix(2))
            totalPickupCount = all.count
            AppLog.pos.info("PosGateVM: \(all.count, privacy: .public) ready-for-pickup tickets")
        } catch {
            let msg = error.localizedDescription
            AppLog.pos.error("PosGateVM: pickup load error — \(msg, privacy: .public)")
            // Non-fatal: pickup strip is optional UI enrichment.
        }
    }

    // MARK: Route actions

    public func selectExistingCustomer(id: Int64) {
        onRouteSelected(.existing(id))
    }

    public func selectCreateNew() {
        onRouteSelected(.createNew)
    }

    public func selectWalkIn() {
        onRouteSelected(.walkIn)
    }

    public func openPickup(id: Int64) {
        onRouteSelected(.openPickup(id))
    }

    public func showAllPickups() {
        isShowingPickupSheet = true
    }
}
#endif
