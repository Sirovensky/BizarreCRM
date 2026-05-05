// §57.4 DispatcherViewModel — drives the iPad dispatcher split view.
//
// Manager/admin role sees all jobs. List column + map placeholder detail.
// Fetches all jobs (no role scoping needed server-side for managers).
// Platform-agnostic for unit testing.

import Foundation
import Observation
import Networking

// MARK: - DispatcherViewModel

@MainActor
@Observable
public final class DispatcherViewModel {

    // MARK: - State

    public enum ListState: Sendable, Equatable {
        case loading
        case loaded([FSJob])
        case empty
        case failed(String)
    }

    public private(set) var listState: ListState = .loading
    public private(set) var selectedJob: FSJob? = nil
    public private(set) var isRefreshing: Bool = false

    // MARK: - Filter state

    public var selectedStatus: FSJobStatus? = nil
    public var assignedTechnicianId: Int64? = nil

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    public func load() async {
        listState = .loading
        await fetch(isRefresh: false)
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        await fetch(isRefresh: true)
    }

    public func applyFilters() async {
        await fetch(isRefresh: false)
    }

    public func selectJob(_ job: FSJob?) {
        selectedJob = job
    }

    // MARK: - Private

    private func fetch(isRefresh: Bool) async {
        if isRefresh { isRefreshing = true }
        defer { if isRefresh { isRefreshing = false } }

        do {
            let response = try await api.listFieldServiceJobs(
                status: selectedStatus,
                assignedTechnicianId: assignedTechnicianId,
                pageSize: 100
            )
            let jobs = response.jobs
            listState = jobs.isEmpty ? .empty : .loaded(jobs)
        } catch {
            listState = .failed(error.localizedDescription)
        }
    }
}
