import Foundation
import Core
import Networking
import Factory

// MARK: - Protocol

public protocol SetupRepository: Sendable {
    func fetchStatus() async throws -> SetupStatusResponse
    func submitStep(_ step: Int, payload: [String: String]) async throws -> Int
    func uploadLogo(data: Data) async throws -> String
    func completeSetup() async throws
}

// MARK: - In-memory offline queue entry

private struct PendingStepOp: Sendable {
    let step: Int
    let payload: [String: String]
    let enqueuedAt: Date
}

// MARK: - Live implementation

public actor SetupRepositoryLive: SetupRepository {
    private let api: APIClient

    // Simple in-memory offline queue. If the network call fails, the op is
    // queued here. On next `submitStep` or explicit `drainQueue()`, we retry.
    // TODO (Phase 2): persist queue via SyncQueueStore for cross-launch durability.
    private var offlineQueue: [PendingStepOp] = []

    public init(api: APIClient) {
        self.api = api
    }

    public func fetchStatus() async throws -> SetupStatusResponse {
        try await api.getSetupStatus()
    }

    public func submitStep(_ step: Int, payload: [String: String]) async throws -> Int {
        await drainQueue()
        let stepPayload = SetupStepPayload(data: payload)
        do {
            let response = try await api.submitSetupStep(step, payload: stepPayload)
            return response.nextStep
        } catch {
            AppLog.sync.warning("Setup step \(step) submit failed, queuing offline: \(error.localizedDescription, privacy: .public)")
            offlineQueue.append(PendingStepOp(step: step, payload: payload, enqueuedAt: Date()))
            return step + 1
        }
    }

    public func uploadLogo(data: Data) async throws -> String {
        // TODO: POST multipart/form-data to /setup/logo when server endpoint is deployed.
        AppLog.ui.info("Logo upload stub — \(data.count, privacy: .public) bytes queued")
        return "https://cdn.bizarrecrm.com/logos/placeholder.png"
    }

    public func completeSetup() async throws {
        await drainQueue()
        _ = try await api.completeSetup()
    }

    private func drainQueue() async {
        guard !offlineQueue.isEmpty else { return }
        var remaining: [PendingStepOp] = []
        for op in offlineQueue {
            do {
                let payload = SetupStepPayload(data: op.payload)
                _ = try await api.submitSetupStep(op.step, payload: payload)
                AppLog.sync.info("Drained queued setup step \(op.step, privacy: .public)")
            } catch {
                remaining.append(op)
            }
        }
        offlineQueue = remaining
    }
}

// MARK: - Factory registration

public extension Container {
    var setupRepository: Factory<any SetupRepository> {
        self { SetupRepositoryLive(api: APIClientImpl()) }
    }
}
