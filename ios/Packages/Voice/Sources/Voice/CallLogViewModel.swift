import Foundation
import Observation
import Networking

/// §42.1 — Backing view-model for `CallLogView`.
///
/// 404 handling contract: the server's voicemails endpoint and the
/// transcript-fetch endpoint are DEFERRED. `load()` catches `httpStatus(404, …)`
/// and transitions to `.comingSoon` so the UI degrades gracefully rather than
/// showing a hard error.
@MainActor
@Observable
public final class CallLogViewModel {

    // MARK: - State machine

    public enum State: Equatable {
        case loading
        case loaded([CallLogEntry])
        case failed(String)
        /// 404 from server — feature not yet deployed on this instance.
        case comingSoon
    }

    /// Direction filter applied to the loaded list. `nil` means "all".
    public enum DirectionFilter: String, CaseIterable, Equatable, Sendable {
        case all       = "all"
        case inbound   = "inbound"
        case outbound  = "outbound"

        public var label: String {
            switch self {
            case .all:      return "All"
            case .inbound:  return "Inbound"
            case .outbound: return "Outbound"
            }
        }
    }

    public private(set) var state: State = .loading

    /// Active direction filter. Changing this re-filters the loaded list immediately
    /// without a new network request (the full list is retained in `.loaded`).
    public var directionFilter: DirectionFilter = .all

    // MARK: - Dependencies

    private let api: APIClient
    private let pageSize: Int

    public init(api: APIClient, pageSize: Int = 50) {
        self.api = api
        self.pageSize = pageSize
    }

    // MARK: - Load

    /// Fetch the call log. On 404, transitions to `.comingSoon`.
    public func load() async {
        state = .loading
        do {
            let calls = try await api.listCalls(pageSize: pageSize)
            state = .loaded(calls)
        } catch let error as APITransportError {
            if case .httpStatus(404, _) = error {
                state = .comingSoon
            } else {
                state = .failed(
                    error.errorDescription ?? "Could not load call log. Please try again."
                )
            }
        } catch {
            state = .failed("Could not load call log. Please try again.")
        }
    }

    // MARK: - Filter

    /// In-memory filter applied to the loaded list. Matches against:
    /// - customer name (case-insensitive)
    /// - phone number (digits-only substring)
    /// - direction ("inbound" / "outbound")
    /// - active `directionFilter` (applied first, before text search)
    ///
    /// Returns the full direction-filtered list when `query` is blank.
    public func filteredCalls(_ query: String) -> [CallLogEntry] {
        guard case .loaded(let calls) = state else { return [] }

        // Apply direction filter first
        let directionFiltered: [CallLogEntry]
        switch directionFilter {
        case .all:
            directionFiltered = calls
        case .inbound:
            directionFiltered = calls.filter { $0.direction == "inbound" }
        case .outbound:
            directionFiltered = calls.filter { $0.direction == "outbound" }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return directionFiltered }

        let lower = trimmed.lowercased()
        let digitsOnly = trimmed.filter(\.isNumber)

        return directionFiltered.filter { entry in
            if let name = entry.customerName, name.lowercased().contains(lower) { return true }
            if entry.direction.lowercased().contains(lower) { return true }
            if !digitsOnly.isEmpty && entry.phoneNumber.filter(\.isNumber).contains(digitsOnly) { return true }
            if entry.phoneNumber.contains(lower) { return true }
            return false
        }
    }
}
