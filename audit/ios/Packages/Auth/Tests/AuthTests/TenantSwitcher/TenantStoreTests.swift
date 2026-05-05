import XCTest
@testable import Auth
import Networking
import Core

// MARK: - TenantStoreTests

final class TenantStoreTests: XCTestCase {

    // MARK: load()

    func test_load_populatesKnownTenants() async throws {
        let repo = StubTenantRepository(tenants: [.acme, .globex])
        let store = TenantStore(repository: repo, api: StubAPIClient())
        let result = try await store.load()
        let known = await store.known
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(known.count, 2)
    }

    func test_load_sortsTenantsBy_lastAccessedAtDescending() async throws {
        let older = Tenant(id: "1", name: "Old", slug: "old", role: "tech",
                          lastAccessedAt: Date(timeIntervalSince1970: 1000))
        let newer = Tenant(id: "2", name: "New", slug: "new", role: "admin",
                          lastAccessedAt: Date(timeIntervalSince1970: 2000))
        let repo = StubTenantRepository(tenants: [older, newer])
        let store = TenantStore(repository: repo, api: StubAPIClient())
        let result = try await store.load()
        XCTAssertEqual(result.first?.id, "2", "Newer last-access should sort first")
    }

    func test_load_setsFirstTenantAsActive_whenNoPreviousPersistence() async throws {
        let repo = StubTenantRepository(tenants: [.acme, .globex])
        let store = TenantStore(repository: repo, api: StubAPIClient())
        try await store.load()
        let active = await store.active
        // First in sorted order (acme has newer lastAccessedAt in fixture)
        XCTAssertNotNil(active)
    }

    func test_load_throwsOnRepositoryFailure() async {
        let repo = StubTenantRepository(error: AppError.network(underlying: nil))
        let store = TenantStore(repository: repo, api: StubAPIClient())
        do {
            _ = try await store.load()
            XCTFail("Expected throw")
        } catch {
            XCTAssertTrue(error is AppError)
        }
    }

    // MARK: switchTo(tenantId:)

    func test_switchTo_updatesActiveTenant() async throws {
        let repo = StubTenantRepository(tenants: [.acme, .globex])
        let store = TenantStore(repository: repo, api: StubAPIClient())
        try await store.load()

        try await store.switchTo(tenantId: Tenant.globex.id)
        let active = await store.active
        XCTAssertEqual(active?.id, Tenant.globex.id)
    }

    func test_switchTo_callsAPIClientSetAuthToken() async throws {
        let api = SpyAPIClient()
        let repo = StubTenantRepository(tenants: [.acme, .globex], switchToken: "new-token-xyz")
        let store = TenantStore(repository: repo, api: api)
        try await store.load()

        try await store.switchTo(tenantId: Tenant.globex.id)
        let token = await api.lastSetAuthToken
        XCTAssertEqual(token, "new-token-xyz")
    }

    func test_switchTo_updatesBaseURL_whenTenantHasDistinctURL() async throws {
        let api = SpyAPIClient()
        let customURL = URL(string: "https://globex.example.com")!
        let globexWithURL = Tenant(id: Tenant.globex.id, name: Tenant.globex.name,
                                   slug: Tenant.globex.slug, baseURL: customURL,
                                   role: Tenant.globex.role)
        let repo = StubTenantRepository(tenants: [.acme, globexWithURL])
        let store = TenantStore(repository: repo, api: api)
        try await store.load()

        try await store.switchTo(tenantId: globexWithURL.id)
        let url = await api.lastSetBaseURL
        XCTAssertEqual(url, customURL)
    }

    func test_switchTo_doesNotChangeBaseURL_whenTenantHasNoDistinctURL() async throws {
        let api = SpyAPIClient()
        let repo = StubTenantRepository(tenants: [.acme, .globex]) // globex has no baseURL
        let store = TenantStore(repository: repo, api: api)
        try await store.load()

        try await store.switchTo(tenantId: Tenant.globex.id)
        let url = await api.lastSetBaseURL
        XCTAssertNil(url, "Should not set base URL when tenant has none")
    }

    func test_switchTo_callsOnTenantSwitchClosure() async throws {
        let repo = StubTenantRepository(tenants: [.acme, .globex])
        let box = TenantBox()
        let store = TenantStore(repository: repo, api: StubAPIClient()) { tenant in
            await box.set(tenant)
        }
        try await store.load()
        try await store.switchTo(tenantId: Tenant.globex.id)
        let received = await box.value
        XCTAssertEqual(received?.id, Tenant.globex.id)
    }

    func test_switchTo_postsNotification() async throws {
        let repo = StubTenantRepository(tenants: [.acme, .globex])
        let store = TenantStore(repository: repo, api: StubAPIClient())
        try await store.load()

        let expectation = expectation(description: "tenantDidSwitch notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .tenantDidSwitch, object: nil, queue: .main
        ) { note in
            let tenant = note.userInfo?["tenant"] as? Tenant
            XCTAssertEqual(tenant?.id, Tenant.globex.id)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await store.switchTo(tenantId: Tenant.globex.id)
        await fulfillment(of: [expectation], timeout: 2)
    }

    func test_switchTo_throwsNotFound_forUnknownTenantId() async throws {
        let repo = StubTenantRepository(tenants: [.acme])
        let store = TenantStore(repository: repo, api: StubAPIClient())
        try await store.load()

        do {
            try await store.switchTo(tenantId: "unknown-id")
            XCTFail("Expected AppError.notFound")
        } catch AppError.notFound {
            // expected
        }
    }

    func test_switchTo_throwsWhenRepositoryFails() async throws {
        let repo = StubTenantRepository(
            tenants: [.acme, .globex],
            switchError: AppError.server(statusCode: 403, message: "Forbidden")
        )
        let store = TenantStore(repository: repo, api: StubAPIClient())
        try await store.load()

        do {
            try await store.switchTo(tenantId: Tenant.globex.id)
            XCTFail("Expected throw")
        } catch {
            XCTAssertTrue(error is AppError)
        }
    }

    // MARK: clearActiveSession()

    func test_clearActiveSession_nilsActiveAndKnown() async throws {
        let repo = StubTenantRepository(tenants: [.acme, .globex])
        let store = TenantStore(repository: repo, api: StubAPIClient())
        try await store.load()

        await store.clearActiveSession()
        let active = await store.active
        let known = await store.known
        XCTAssertNil(active)
        XCTAssertTrue(known.isEmpty)
    }
}

// MARK: - Fixtures

private extension Tenant {
    static let acme = Tenant(
        id: "tenant-acme",
        name: "Acme Repair",
        slug: "acme",
        role: "admin",
        lastAccessedAt: Date(timeIntervalSince1970: 2000)
    )
    static let globex = Tenant(
        id: "tenant-globex",
        name: "Globex Tech",
        slug: "globex",
        role: "tech",
        lastAccessedAt: Date(timeIntervalSince1970: 1000)
    )
}

// MARK: - Stubs

private final class StubTenantRepository: TenantRepository, @unchecked Sendable {
    private let tenants: [Tenant]
    private let error: (any Error)?
    private let switchToken: String
    private let switchError: (any Error)?

    init(
        tenants: [Tenant] = [],
        error: (any Error)? = nil,
        switchToken: String = "stub-token",
        switchError: (any Error)? = nil
    ) {
        self.tenants = tenants
        self.error = error
        self.switchToken = switchToken
        self.switchError = switchError
    }

    func loadTenants() async throws -> [Tenant] {
        if let error { throw error }
        return tenants
    }

    func switchTenant(tenantId: String) async throws -> (accessToken: String, refreshToken: String) {
        if let err = switchError { throw err }
        return (switchToken, "stub-refresh")
    }

    func revokeTenantSession() async throws {}
}

private actor StubAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

private actor SpyAPIClient: APIClient {
    private(set) var lastSetAuthToken: String? = nil
    private(set) var lastSetBaseURL: URL? = nil

    func setAuthToken(_ token: String?) async { lastSetAuthToken = token }
    func setBaseURL(_ url: URL?) async { lastSetBaseURL = url }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

private actor TenantBox {
    private(set) var value: Tenant?
    func set(_ tenant: Tenant) { value = tenant }
}
