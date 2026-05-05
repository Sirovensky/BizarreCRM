import Foundation
import Core
import Networking

// MARK: - CashPeriodLockRepositoryImpl (§39.4 period lock — live)

/// Live implementation of `CashPeriodLockRepository`.
///
/// All APIClient calls must live in `*Repository.swift` or `*Endpoints.swift`
/// files per the §20 containment rule (sdk-ban.sh checks filenames).
public final class CashPeriodLockRepositoryImpl: CashPeriodLockRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listLocks() async throws -> [CashPeriodLock] {
        struct Envelope: Decodable, Sendable {
            let success: Bool
            let data: [CashPeriodLock]?
        }
        let env = try await api.get("/pos/period-locks", as: Envelope.self)
        return env.data ?? []
    }

    public func lockPeriod(_ request: CashPeriodLockRequest) async throws -> CashPeriodLock {
        struct Envelope: Decodable, Sendable {
            let success: Bool
            let data: CashPeriodLock?
        }
        let env = try await api.post(
            "/pos/period-locks",
            body: request,
            as: Envelope.self
        )
        guard let lock = env.data else {
            throw AppError.envelope(reason: "Period lock response had no data")
        }
        AppLog.pos.info(
            "CashPeriodLockRepository: period locked id=\(lock.id, privacy: .private)"
        )
        return lock
    }

    public func unlockPeriod(id: Int64, request: CashPeriodUnlockRequest) async throws {
        // Use POST to a dedicated unlock sub-resource so we can include the
        // manager PIN body (DELETE without body is insufficient for the audit trail).
        struct Envelope: Decodable, Sendable { let success: Bool }
        _ = try await api.post(
            "/pos/period-locks/\(id)/unlock",
            body: request,
            as: Envelope.self
        )
        AppLog.pos.warning(
            "CashPeriodLockRepository: manager override — period \(id, privacy: .private) unlocked"
        )
    }
}
