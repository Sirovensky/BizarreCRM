import Testing
import Foundation
@testable import Notifications
@testable import Networking

// MARK: - StubPrefsAPIClient

actor StubPrefsAPIClient: APIClient {
    var getResponse: NotificationPrefsResponse?
    var putResponse: NotificationPrefsResponse?
    var shouldFail: Bool = false

    func setGetResponse(_ r: NotificationPrefsResponse?) { getResponse = r }
    func setPutResponse(_ r: NotificationPrefsResponse?) { putResponse = r }
    func setShouldFail(_ f: Bool) { shouldFail = f }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldFail { throw APITransportError.invalidResponse }
        guard let resp = getResponse else { throw APITransportError.invalidResponse }
        guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if shouldFail { throw APITransportError.invalidResponse }
        guard let resp = putResponse ?? getResponse else { throw APITransportError.invalidResponse }
        guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - NotifPrefsRepositoryTests

@Suite("NotifPrefsRepositoryImpl")
struct NotifPrefsRepositoryImplTests {

    // MARK: - Helpers

    static func makeServerRows(enabled: Bool = true) -> [NotificationPrefRow] {
        NotificationEvent.allCases.flatMap { event in
            ["push", "in_app", "email", "sms"].map { channel in
                NotificationPrefRow(
                    eventType: event.rawValue,
                    channel: channel,
                    enabled: enabled,
                    quietHours: nil
                )
            }
        }
    }

    static func makeFullResponse(enabled: Bool = true) -> NotificationPrefsResponse {
        NotificationPrefsResponse(
            preferences: makeServerRows(enabled: enabled),
            eventTypes: NotificationEvent.allCases.map { $0.rawValue },
            channels: ["push", "in_app", "email", "sms"]
        )
    }

    // MARK: - fetchAll

    @Test("fetchAll returns one preference per event")
    func fetchAllCount() async throws {
        let api = StubPrefsAPIClient()
        await api.setGetResponse(makeFullResponse())
        let repo = NotifPrefsRepositoryImpl(api: api)
        let prefs = try await repo.fetchAll()
        #expect(prefs.count == NotificationEvent.allCases.count)
    }

    @Test("fetchAll maps server 'enabled=true' to pushEnabled=true")
    func fetchAllEnabled() async throws {
        let api = StubPrefsAPIClient()
        await api.setGetResponse(makeFullResponse(enabled: true))
        let repo = NotifPrefsRepositoryImpl(api: api)
        let prefs = try await repo.fetchAll()
        #expect(prefs.allSatisfy { $0.pushEnabled })
    }

    @Test("fetchAll maps server 'enabled=false' to pushEnabled=false")
    func fetchAllDisabled() async throws {
        let api = StubPrefsAPIClient()
        await api.setGetResponse(makeFullResponse(enabled: false))
        let repo = NotifPrefsRepositoryImpl(api: api)
        let prefs = try await repo.fetchAll()
        #expect(prefs.allSatisfy { !$0.pushEnabled })
    }

    @Test("fetchAll throws on network error")
    func fetchAllThrows() async {
        let api = StubPrefsAPIClient()
        await api.setShouldFail(true)
        let repo = NotifPrefsRepositoryImpl(api: api)
        do {
            _ = try await repo.fetchAll()
            Issue.record("Expected fetchAll to throw")
        } catch {
            // Expected
        }
    }

    @Test("fetchAll backfills missing events with defaults")
    func fetchAllBackfillsMissing() async throws {
        // Only return rows for one event
        let singleEvent = NotificationEvent.ticketAssigned
        let rows = ["push", "in_app", "email", "sms"].map { channel in
            NotificationPrefRow(eventType: singleEvent.rawValue, channel: channel,
                                enabled: true, quietHours: nil)
        }
        let response = NotificationPrefsResponse(
            preferences: rows,
            eventTypes: [singleEvent.rawValue],
            channels: ["push", "in_app", "email", "sms"]
        )
        let api = StubPrefsAPIClient()
        await api.setGetResponse(response)
        let repo = NotifPrefsRepositoryImpl(api: api)
        let prefs = try await repo.fetchAll()
        // Must return all events, not just the one returned from server
        #expect(prefs.count == NotificationEvent.allCases.count)
    }

    @Test("fetchAll maps quiet hours when present")
    func fetchAllWithQuietHours() async throws {
        let qh = NotificationPrefQuietHours(start: 22 * 60, end: 7 * 60, allowCriticalOverride: true)
        let rows = NotificationEvent.allCases.flatMap { event in
            ["push", "in_app", "email", "sms"].map { channel in
                NotificationPrefRow(eventType: event.rawValue, channel: channel,
                                    enabled: true, quietHours: channel == "push" ? qh : nil)
            }
        }
        let response = NotificationPrefsResponse(
            preferences: rows,
            eventTypes: NotificationEvent.allCases.map { $0.rawValue },
            channels: ["push", "in_app", "email", "sms"]
        )
        let api = StubPrefsAPIClient()
        await api.setGetResponse(response)
        let repo = NotifPrefsRepositoryImpl(api: api)
        let prefs = try await repo.fetchAll()
        #expect(prefs.allSatisfy { $0.quietHours != nil })
    }

    // MARK: - batchUpdate

    @Test("batchUpdate sends items and returns updated prefs")
    func batchUpdate() async throws {
        let api = StubPrefsAPIClient()
        let resp = makeFullResponse(enabled: false)
        await api.setGetResponse(resp)
        await api.setPutResponse(resp)
        let repo = NotifPrefsRepositoryImpl(api: api)
        let toSend = [NotificationPreference.defaultPreference(for: .ticketAssigned)]
        let result = try await repo.batchUpdate(toSend)
        #expect(result.count == NotificationEvent.allCases.count)
    }

    @Test("batchUpdate throws on failure")
    func batchUpdateThrows() async {
        let api = StubPrefsAPIClient()
        await api.setShouldFail(true)
        let repo = NotifPrefsRepositoryImpl(api: api)
        do {
            _ = try await repo.batchUpdate([.defaultPreference(for: .ticketAssigned)])
            Issue.record("Expected batchUpdate to throw")
        } catch {
            // Expected
        }
    }
}
