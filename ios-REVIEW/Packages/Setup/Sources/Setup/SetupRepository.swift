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
    func seedRepairPricingDefaults(_ request: RepairPricingSeedDefaultsRequest) async throws -> RepairPricingSeedDefaultsResponse
    func saveRepairPricingSpreadsheetPrices(_ prices: [SetupSpreadsheetPriceDraft]) async throws
    func saveRepairPricingAutoMarginSettings(_ settings: RepairPricingAutoMarginSettings) async throws -> RepairPricingAutoMarginSettings
    func fetchRepairPricingMatrixPreview(category: String, limit: Int) async throws -> RepairPricingMatrixResponse
}

private struct SetupRepairPricingRepositoryUnavailable: LocalizedError, Sendable {
    var errorDescription: String? {
        "Repair pricing setup is not available in this repository."
    }
}

public extension SetupRepository {
    func seedRepairPricingDefaults(_ request: RepairPricingSeedDefaultsRequest) async throws -> RepairPricingSeedDefaultsResponse {
        throw SetupRepairPricingRepositoryUnavailable()
    }

    func saveRepairPricingSpreadsheetPrices(_ prices: [SetupSpreadsheetPriceDraft]) async throws {
        throw SetupRepairPricingRepositoryUnavailable()
    }

    func saveRepairPricingAutoMarginSettings(_ settings: RepairPricingAutoMarginSettings) async throws -> RepairPricingAutoMarginSettings {
        throw SetupRepairPricingRepositoryUnavailable()
    }

    func fetchRepairPricingMatrixPreview(category: String, limit: Int) async throws -> RepairPricingMatrixResponse {
        throw SetupRepairPricingRepositoryUnavailable()
    }
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
        let response = try await api.uploadSetupLogo(data, mimeType: "image/jpeg")
        let url = response.url ?? "https://cdn.bizarrecrm.com/logos/placeholder.png"
        AppLog.ui.info("Logo uploaded via setup endpoint: \(url, privacy: .public)")
        return url
    }

    public func completeSetup() async throws {
        await drainQueue()
        _ = try await api.completeSetup()
    }

    public func seedRepairPricingDefaults(_ request: RepairPricingSeedDefaultsRequest) async throws -> RepairPricingSeedDefaultsResponse {
        try await api.seedRepairPricingDefaults(request)
    }

    public func saveRepairPricingSpreadsheetPrices(_ prices: [SetupSpreadsheetPriceDraft]) async throws {
        for price in prices where price.shouldPersist {
            guard let laborPrice = price.laborPrice else { continue }
            let request = RepairPricingPriceWriteRequest(
                deviceModelId: price.deviceModelId,
                repairServiceId: price.repairServiceId,
                laborPrice: laborPrice,
                defaultGrade: "aftermarket",
                isActive: 1,
                isCustom: 1,
                autoMarginEnabled: 0
            )

            if let priceId = price.priceId {
                _ = try await api.updateRepairPricingPrice(priceId: priceId, request: request)
            } else {
                _ = try await api.createRepairPricingPrice(request)
            }
        }
    }

    public func saveRepairPricingAutoMarginSettings(_ settings: RepairPricingAutoMarginSettings) async throws -> RepairPricingAutoMarginSettings {
        try await api.updateRepairPricingAutoMarginSettings(settings)
    }

    public func fetchRepairPricingMatrixPreview(category: String, limit: Int) async throws -> RepairPricingMatrixResponse {
        try await api.fetchRepairPricingMatrix(category: category, limit: limit)
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
