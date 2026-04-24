// §57.1 JobListViewModel — drives the tech job list screen.
//
// Fetches GET /field-service/jobs (paginated, filtered by role on server).
// Technicians see their own assigned jobs; managers see all.
// Designed to be platform-agnostic for unit testing (no SwiftUI imports).

import Foundation
import Observation
import Networking

// MARK: - JobListViewModel

@MainActor
@Observable
public final class JobListViewModel {

    // MARK: - State

    public enum ViewState: Sendable, Equatable {
        case idle
        case loading
        case loaded([FSJob])
        case failed(String)
        case empty
    }

    public private(set) var state: ViewState = .idle
    public private(set) var isRefreshing: Bool = false

    // MARK: - Filter state

    public var selectedStatus: FSJobStatus? = nil
    public var fromDate: String? = nil
    public var toDate: String? = nil

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    /// Initial load.
    public func load() async {
        guard state == .idle || state == .failed("") || {
            if case .failed = state { return true }
            return false
        }() else { return }
        await fetch(isRefresh: false)
    }

    /// Pull-to-refresh.
    public func refresh() async {
        guard !isRefreshing else { return }
        await fetch(isRefresh: true)
    }

    /// Re-apply current filters (called when filter values change).
    public func applyFilters() async {
        await fetch(isRefresh: false)
    }

    // MARK: - Private

    private func fetch(isRefresh: Bool) async {
        if isRefresh {
            isRefreshing = true
        } else {
            state = .loading
        }
        defer {
            if isRefresh { isRefreshing = false }
        }

        do {
            let response = try await api.listFieldServiceJobs(
                status: selectedStatus,
                fromDate: fromDate,
                toDate: toDate
            )
            let jobs = response.jobs
            state = jobs.isEmpty ? .empty : .loaded(jobs)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
