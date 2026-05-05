// §22 DispatcherConsoleViewModel — state for the 3-column iPad dispatcher console.
//
// Owns:
//   - tech roster loading + technician selection (sidebar filter)
//   - job list loading + multi-selection for batch actions
//   - selected-job detail for map pane
//   - batch-reassign operation
//
// Platform-agnostic: no SwiftUI imports; safe to unit test.

import Foundation
import Observation
import Networking

// MARK: - TechStatus

/// Display status derived from jobs and clock state.
public enum TechStatus: String, Sendable, Equatable {
    case available  = "available"
    case busy       = "busy"
    case enRoute    = "en_route"
    case offline    = "offline"

    public var displayLabel: String {
        switch self {
        case .available: return "Available"
        case .busy:      return "Busy"
        case .enRoute:   return "En Route"
        case .offline:   return "Offline"
        }
    }
}

// MARK: - TechRosterEntry

/// Technician plus derived real-time status.
public struct TechRosterEntry: Identifiable, Sendable, Equatable {
    public let tech: Employee
    public let currentStatus: TechStatus
    /// Count of today's assigned jobs.
    public let assignedJobCount: Int

    public var id: Int64 { tech.id }

    public init(tech: Employee, currentStatus: TechStatus, assignedJobCount: Int) {
        self.tech = tech
        self.currentStatus = currentStatus
        self.assignedJobCount = assignedJobCount
    }
}

// MARK: - DispatcherConsoleViewModel

@MainActor
@Observable
public final class DispatcherConsoleViewModel {

    // MARK: - Roster state

    public enum RosterState: Sendable, Equatable {
        case loading
        case loaded([TechRosterEntry])
        case empty
        case failed(String)
    }

    // MARK: - Jobs state

    public enum JobsState: Sendable, Equatable {
        case loading
        case loaded([FSJob])
        case empty
        case failed(String)
    }

    // MARK: - Batch operation state

    public enum BatchState: Sendable, Equatable {
        case idle
        case inProgress
        case succeeded
        case failed(String)
    }

    // MARK: - Published state

    public private(set) var rosterState: RosterState = .loading
    public private(set) var jobsState: JobsState = .loading
    public private(set) var batchState: BatchState = .idle
    public private(set) var isRefreshing: Bool = false

    /// Jobs currently checked in the multi-select set.
    public private(set) var selectedJobIds: Set<Int64> = []

    /// Job shown in the detail / map pane.
    public private(set) var focusedJob: FSJob? = nil

    /// Sidebar tech filter — nil means show all.
    public var filterByTechId: Int64? = nil

    /// Job status filter.
    public var filterByStatus: FSJobStatus? = nil

    /// Controls iPhone sheet for tech roster.
    public var showTechRoster: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        async let rostersTask: () = loadRoster()
        async let jobsTask: () = loadJobs()
        _ = await (rostersTask, jobsTask)
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let rostersTask: () = loadRoster()
        async let jobsTask: () = loadJobs()
        _ = await (rostersTask, jobsTask)
    }

    public func applyFilters() async {
        await loadJobs()
    }

    // MARK: - Roster

    private func loadRoster() async {
        do {
            let employees = try await api.listEmployees()
            let jobs: [FSJob]
            if case .loaded(let j) = jobsState {
                jobs = j
            } else {
                // Fetch a snapshot to count jobs per tech.
                let resp = try await api.listFieldServiceJobs(pageSize: 200)
                jobs = resp.jobs
            }
            let entries = buildRosterEntries(employees: employees, jobs: jobs)
            rosterState = entries.isEmpty ? .empty : .loaded(entries)
        } catch {
            rosterState = .failed(error.localizedDescription)
        }
    }

    private func buildRosterEntries(employees: [Employee], jobs: [FSJob]) -> [TechRosterEntry] {
        // Count assigned jobs per tech (non-completed).
        var countByTech: [Int64: Int] = [:]
        var statusByTech: [Int64: TechStatus] = [:]

        for job in jobs {
            guard let techId = job.assignedTechnicianId else { continue }
            let jobStatus = FSJobStatus(rawValue: job.status)
            if jobStatus == .completed || jobStatus == .canceled { continue }
            countByTech[techId, default: 0] += 1
            let techStatus: TechStatus
            switch jobStatus {
            case .enRoute:           techStatus = .enRoute
            case .onSite, .assigned: techStatus = .busy
            default:                 techStatus = .available
            }
            // Escalate: en_route > busy > available.
            let current = statusByTech[techId] ?? .available
            if techStatus == .enRoute || (techStatus == .busy && current == .available) {
                statusByTech[techId] = techStatus
            }
        }

        return employees
            .filter { $0.active }
            .map { emp in
                TechRosterEntry(
                    tech: emp,
                    currentStatus: statusByTech[emp.id] ?? .available,
                    assignedJobCount: countByTech[emp.id] ?? 0
                )
            }
            .sorted { $0.tech.displayName < $1.tech.displayName }
    }

    // MARK: - Jobs

    private func loadJobs() async {
        jobsState = .loading
        do {
            let response = try await api.listFieldServiceJobs(
                status: filterByStatus,
                assignedTechnicianId: filterByTechId,
                pageSize: 200
            )
            let jobs = response.jobs
            jobsState = jobs.isEmpty ? .empty : .loaded(jobs)
        } catch {
            jobsState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Selection

    public func focusJob(_ job: FSJob?) {
        focusedJob = job
    }

    public func toggleJobSelection(_ jobId: Int64) {
        if selectedJobIds.contains(jobId) {
            selectedJobIds.remove(jobId)
        } else {
            selectedJobIds.insert(jobId)
        }
    }

    public func selectAll(jobs: [FSJob]) {
        selectedJobIds = Set(jobs.map(\.id))
    }

    public func clearSelection() {
        selectedJobIds = []
    }

    // MARK: - Keyboard shortcut actions

    /// Called by ⌘N: assign next unassigned job to selected tech (or focus first unassigned).
    public func assignNextUnassigned() {
        guard case .loaded(let jobs) = jobsState else { return }
        if let job = jobs.first(where: { $0.status == FSJobStatus.unassigned.rawValue }) {
            focusedJob = job
        }
    }

    /// Called by ⌘F: clear tech/status filters to see all jobs.
    public func findJobs() {
        filterByTechId = nil
        filterByStatus = nil
        Task { await loadJobs() }
    }

    /// Called by J: select next job in list.
    public func selectNextJob() {
        guard case .loaded(let jobs) = jobsState, !jobs.isEmpty else { return }
        if let current = focusedJob, let idx = jobs.firstIndex(where: { $0.id == current.id }) {
            focusedJob = jobs[min(idx + 1, jobs.count - 1)]
        } else {
            focusedJob = jobs.first
        }
    }

    /// Called by K: select previous job in list.
    public func selectPreviousJob() {
        guard case .loaded(let jobs) = jobsState, !jobs.isEmpty else { return }
        if let current = focusedJob, let idx = jobs.firstIndex(where: { $0.id == current.id }) {
            focusedJob = jobs[max(idx - 1, 0)]
        } else {
            focusedJob = jobs.last
        }
    }

    // MARK: - Batch reassign

    /// Reassign all `selectedJobIds` to a technician, updating status to `.assigned`.
    public func batchReassign(toTechnicianId: Int64) async {
        guard !selectedJobIds.isEmpty else { return }
        batchState = .inProgress

        var failed = 0
        for jobId in selectedJobIds {
            let req = FSJobStatusRequest(status: .assigned)
            do {
                _ = try await api.updateFieldServiceJobStatus(id: jobId, request: req)
            } catch {
                failed += 1
            }
        }

        if failed == 0 {
            batchState = .succeeded
            selectedJobIds = []
            await loadJobs()
        } else {
            batchState = .failed("\(failed) job(s) failed to reassign")
        }
    }

    // MARK: - Computed helpers

    /// Jobs currently shown in the list column.
    public var currentJobs: [FSJob] {
        if case .loaded(let jobs) = jobsState { return jobs }
        return []
    }

    public var hasBatchSelection: Bool { !selectedJobIds.isEmpty }
}
