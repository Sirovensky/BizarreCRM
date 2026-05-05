import Foundation
import Observation
import Networking
import Core

// MARK: - TimeOffViewModel
//
// Loads and submits time-off requests against:
//   POST /api/v1/time-off   — self-service submission
//   GET  /api/v1/time-off   — list own (or all for managers)
//
// Injectable userIdProvider + date formatter for deterministic tests.

@MainActor
@Observable
public final class TimeOffViewModel {

    // MARK: - List state

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var requests: [TimeOffRequest] = []
    /// Filter applied to the list load. Nil = show all statuses.
    public var statusFilter: TimeOffStatus? = nil

    // MARK: - Submit state

    public enum SubmitState: Sendable, Equatable {
        case idle, submitting, submitted, failed(String)
    }

    public private(set) var submitState: SubmitState = .idle

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored public var userIdProvider: @Sendable () async -> Int64

    // MARK: - Init

    public init(
        api: APIClient,
        userIdProvider: @escaping @Sendable () async -> Int64 = { 0 }
    ) {
        self.api = api
        self.userIdProvider = userIdProvider
    }

    // MARK: - Load

    public func load() async {
        loadState = .loading
        let userId = await userIdProvider()
        do {
            let result = try await api.listTimeOffRequests(
                userId: userId > 0 ? userId : nil,
                status: statusFilter
            )
            requests = result
            loadState = .loaded
        } catch {
            AppLog.ui.error("TimeOff load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Submit

    /// Submit a time-off request. Appends the new request to `requests` on success.
    ///
    /// - Parameters:
    ///   - startDate: ISO-8601 date string ("yyyy-MM-dd").
    ///   - endDate:   ISO-8601 date string ("yyyy-MM-dd"). Must be >= startDate.
    ///   - kind:      Request kind (pto, sick, unpaid).
    ///   - reason:    Optional note (max 1 000 chars per server policy).
    public func submit(
        startDate: String,
        endDate: String,
        kind: TimeOffKind,
        reason: String?
    ) async {
        submitState = .submitting
        let body = CreateTimeOffRequest(
            startDate: startDate,
            endDate: endDate,
            kind: kind,
            reason: reason?.isEmpty == false ? reason : nil
        )
        do {
            let created = try await api.submitTimeOff(body)
            requests.insert(created, at: 0)
            submitState = .submitted
        } catch {
            AppLog.ui.error("TimeOff submit failed: \(error.localizedDescription, privacy: .public)")
            submitState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Computed helpers

    public var pendingRequests: [TimeOffRequest] {
        requests.filter { $0.status == .pending }
    }
}
