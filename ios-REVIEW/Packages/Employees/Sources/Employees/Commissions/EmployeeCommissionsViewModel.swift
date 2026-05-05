import Foundation
import Observation
import Networking
import Core

// MARK: - EmployeeCommissionsViewModel
//
// Loads GET /api/v1/employees/:id/commissions.
// Auth: self or admin (server-enforced).
// Injectable userIdProvider and now() for deterministic unit tests.

@MainActor
@Observable
public final class EmployeeCommissionsViewModel {

    // MARK: - State

    public enum LoadState: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var commissions: [EmployeeCommission] = []
    public private(set) var totalAmount: Double = 0

    /// ISO-8601 date lower bound ("yyyy-MM-dd"). Nil = no filter.
    public var fromDate: String? = nil
    /// ISO-8601 date upper bound ("yyyy-MM-dd"). Nil = no filter.
    public var toDate: String? = nil

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

    // MARK: - Public API

    public func load() async {
        loadState = .loading
        let userId = await userIdProvider()
        do {
            let response = try await api.getEmployeeCommissions(
                userId: userId,
                fromDate: fromDate,
                toDate: toDate
            )
            commissions = response.commissions
            totalAmount = response.totalAmount
            loadState = .loaded
        } catch {
            AppLog.ui.error("EmployeeCommissions load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    public var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: totalAmount)) ?? "$\(totalAmount)"
    }
}
