import Testing
import Foundation
import Networking
@testable import KioskMode

// MARK: - Mock APIClient

final class MockAPIClient: @unchecked Sendable {
    var enterResult: Result<TrainingEnterResponse, Error> = .success(
        TrainingEnterResponse(demoTenantToken: "demo-abc", seededData: true)
    )
    var resetResult: Result<TrainingResetResponse, Error> = .success(
        TrainingResetResponse(ok: true)
    )
    var statusResult: Result<TrainingStatusResponse, Error> = .success(
        TrainingStatusResponse(active: false, tenantId: "demo-tenant")
    )

    var enterCallCount = 0
    var resetCallCount = 0
}

extension MockAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "training/status", let r = statusResult as? Result<T, Error> {
            return try r.get()
        }
        throw URLError(.badURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path == "training/enter" {
            enterCallCount += 1
            if let r = enterResult as? Result<T, Error> { return try r.get() }
        }
        if path == "training/reset-demo" {
            resetCallCount += 1
            if let r = resetResult as? Result<T, Error> { return try r.get() }
        }
        throw URLError(.badURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.badURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

// MARK: - TokenRecorder (Swift 6 concurrency-safe capture)

@MainActor
final class TokenRecorder {
    var lastToken: String? = "initial"
    var callCount: Int = 0

    func record(_ token: String?) {
        lastToken = token
        callCount += 1
    }

    var swap: @Sendable @MainActor (String?) -> Void { { [self] t in self.record(t) } }
}

// MARK: - TrainingModeManagerTests

@Suite("TrainingModeManager")
@MainActor
struct TrainingModeManagerTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test-training-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    // MARK: - Persistence

    @Test("Starts inactive by default")
    func startsInactive() {
        let mock = MockAPIClient()
        let manager = TrainingModeManager(api: mock, defaults: makeDefaults(), tokenSwap: { _ in })
        #expect(manager.isActive == false)
    }

    @Test("Restores persisted active state")
    func restoresPersistence() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: TrainingModeManager.defaultsKey)
        let mock = MockAPIClient()
        let manager = TrainingModeManager(api: mock, defaults: defaults, tokenSwap: { _ in })
        #expect(manager.isActive == true)
    }

    // MARK: - Enter training mode

    @Test("Enter training mode sets isActive and swaps token")
    func enterSetsActiveAndSwapsToken() async {
        let mock = MockAPIClient()
        let defaults = makeDefaults()
        let recorder = TokenRecorder()
        let manager = TrainingModeManager(api: mock, defaults: defaults, tokenSwap: recorder.swap)

        await manager.enterTrainingMode()

        #expect(manager.isActive == true)
        #expect(recorder.lastToken == "demo-abc")
        #expect(defaults.bool(forKey: TrainingModeManager.defaultsKey) == true)
        #expect(mock.enterCallCount == 1)
    }

    @Test("Enter training mode is idempotent when already active")
    func enterIdempotent() async {
        let mock = MockAPIClient()
        let manager = TrainingModeManager(api: mock, defaults: makeDefaults(), tokenSwap: { _ in })
        await manager.enterTrainingMode()
        let countAfterFirst = mock.enterCallCount
        await manager.enterTrainingMode()
        #expect(mock.enterCallCount == countAfterFirst)
    }

    @Test("Enter training mode surfaces error on failure")
    func enterSurfacesError() async {
        let mock = MockAPIClient()
        mock.enterResult = .failure(URLError(.notConnectedToInternet))
        let manager = TrainingModeManager(api: mock, defaults: makeDefaults(), tokenSwap: { _ in })

        await manager.enterTrainingMode()

        #expect(manager.isActive == false)
        #expect(manager.errorMessage != nil)
    }

    // MARK: - Exit training mode

    @Test("Exit training mode clears isActive and reverts token")
    func exitClearsActive() async {
        let mock = MockAPIClient()
        let defaults = makeDefaults()
        let recorder = TokenRecorder()
        let manager = TrainingModeManager(api: mock, defaults: defaults, tokenSwap: recorder.swap)
        await manager.enterTrainingMode()
        manager.exitTrainingMode()

        #expect(manager.isActive == false)
        #expect(recorder.lastToken == nil)
        #expect(defaults.bool(forKey: TrainingModeManager.defaultsKey) == false)
    }

    @Test("Exit training mode is idempotent when already inactive")
    func exitIdempotent() {
        let mock = MockAPIClient()
        let recorder = TokenRecorder()
        let manager = TrainingModeManager(api: mock, defaults: makeDefaults(), tokenSwap: recorder.swap)
        manager.exitTrainingMode()
        #expect(recorder.callCount == 0)
    }

    // MARK: - Reset demo data

    @Test("Reset calls API when active")
    func resetCallsAPI() async {
        let mock = MockAPIClient()
        let manager = TrainingModeManager(api: mock, defaults: makeDefaults(), tokenSwap: { _ in })
        await manager.enterTrainingMode()
        await manager.resetDemoData()
        #expect(mock.resetCallCount == 1)
    }

    @Test("Reset does nothing when not active")
    func resetNoOpWhenInactive() async {
        let mock = MockAPIClient()
        let manager = TrainingModeManager(api: mock, defaults: makeDefaults(), tokenSwap: { _ in })
        await manager.resetDemoData()
        #expect(mock.resetCallCount == 0)
    }

    @Test("Reset surfaces error on failure")
    func resetSurfacesError() async {
        let mock = MockAPIClient()
        mock.resetResult = .failure(URLError(.timedOut))
        let manager = TrainingModeManager(api: mock, defaults: makeDefaults(), tokenSwap: { _ in })
        await manager.enterTrainingMode()
        await manager.resetDemoData()
        #expect(manager.errorMessage != nil)
    }
}
