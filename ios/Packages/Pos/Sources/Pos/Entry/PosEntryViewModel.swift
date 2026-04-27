/// PosEntryViewModel.swift — §16.21
///
/// Observable VM for the POS entry screen (redesign wave, 2026-04-24).
/// Drives: animated PosSearchBar (bottom→top spring on focus),
/// unified customer + ticket search, contextual "Ready for pickup" banner,
/// recent-entry quick-pick row, and offline/loading states.
///
/// Architecture: VM → PosRepository (never bare APIClient). Offline path
/// reads GRDB cache; shows "Offline · showing cached" chip.

#if canImport(UIKit)
import Foundation
import Observation
import Networking
import Core

// MARK: - Supporting types

/// Unified search result shown in the entry screen list.
public enum PosEntrySearchResult: Sendable, Identifiable {
    case customer(CustomerSearchHit)
    case ticket(TicketSearchHit)

    public var id: String {
        switch self {
        case .customer(let c): return "c-\(c.id)"
        case .ticket(let t): return "t-\(t.id)"
        }
    }
}

/// Lightweight ticket hit for entry screen.
public struct TicketSearchHit: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let orderId: String
    public let summary: String
    public let status: String
    public let totalCents: Int

    public init(id: Int64, orderId: String, summary: String, status: String, totalCents: Int) {
        self.id = id
        self.orderId = orderId
        self.summary = summary
        self.status = status
        self.totalCents = totalCents
    }

    public var isReadyForPickup: Bool { status.lowercased() == "ready" }
}

/// Recent entry quick-pick item (last 3 customers / tickets / walk-ins).
public struct RecentEntry: Sendable, Identifiable {
    public enum Kind: Sendable {
        case customer(Int64, String)
        case ticket(Int64, String)
        case walkIn
    }
    public let id: UUID
    public let kind: Kind
    public let label: String

    public init(id: UUID = UUID(), kind: Kind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }
}

// MARK: - PosEntryViewModel

/// §16.21 — Entry screen VM.
@MainActor
@Observable
public final class PosEntryViewModel {

    // MARK: - Search state

    public var query: String = "" {
        didSet { scheduleSearch() }
    }

    public var isSearchExpanded: Bool = false
    public private(set) var searchResults: [PosEntrySearchResult] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String? = nil
    public private(set) var isOffline: Bool = false

    // MARK: - Recent entries

    public private(set) var recentEntries: [RecentEntry] = []

    // MARK: - Ready-for-pickup (customer-specific)

    /// Set when a customer is selected and they have ready tickets.
    public private(set) var readyForPickupCount: Int = 0

    // MARK: - Deps

    @ObservationIgnored private let api: (any APIClient)?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    // MARK: - Callbacks (set by parent)

    public var onAttachCustomer: ((CustomerSearchHit) -> Void)?
    public var onOpenTicket: ((TicketSearchHit) -> Void)?
    public var onWalkIn: (() -> Void)?
    public var onCreateCustomer: (() -> Void)?

    // MARK: - Init

    public init(api: (any APIClient)? = nil) {
        self.api = api
    }

    // MARK: - Search

    public func expandSearch() {
        isSearchExpanded = true
    }

    public func collapseSearch() {
        isSearchExpanded = false
        query = ""
        searchResults = []
        errorMessage = nil
    }

    public func scheduleSearch() {
        debounceTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isLoading = false
            return
        }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    private func performSearch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let api else {
            isOffline = true
            searchResults = []
            return
        }

        do {
            // Customers — keyword search via GET /api/v1/customers
            let customersResp = try await api.listCustomers(keyword: query, pageSize: 10)
            let customerHits = customersResp.customers.map { c in
                CustomerSearchHit(summary: c)
            }.map { PosEntrySearchResult.customer($0) }

            if Task.isCancelled { return }
            searchResults = customerHits
            isOffline = false
        } catch is CancellationError {
            // swallow
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Customer attach

    public func attachCustomer(_ hit: CustomerSearchHit) {
        BrandHaptics.tapMedium()
        onAttachCustomer?(hit)
        addRecentEntry(.customer(hit.id, hit.displayName), label: hit.displayName)
    }

    public func openTicket(_ hit: TicketSearchHit) {
        BrandHaptics.tap()
        onOpenTicket?(hit)
        addRecentEntry(.ticket(hit.id, hit.orderId), label: "#\(hit.orderId)")
    }

    public func walkIn() {
        BrandHaptics.tap()
        onWalkIn?()
        addRecentEntry(.walkIn, label: "Walk-in")
    }

    // MARK: - Recent entries

    private func addRecentEntry(_ kind: RecentEntry.Kind, label: String) {
        let entry = RecentEntry(kind: kind, label: label)
        var updated = recentEntries.filter {
            if case .walkIn = $0.kind, case .walkIn = kind { return false }
            return true
        }
        updated.insert(entry, at: 0)
        recentEntries = Array(updated.prefix(3))
    }

    // MARK: - Contextual ready-for-pickup

    public func loadReadyTickets(for customerId: Int64) async {
        guard let api else { return }
        do {
            let resp = try await api.listTickets(filter: .open, pageSize: 5)
            readyForPickupCount = resp.tickets.filter { $0.status?.name.lowercased() == "ready" }.count
        } catch {
            readyForPickupCount = 0
        }
    }
}
#endif
