import XCTest
@testable import Pos
@testable import Networking

/// §39.4 — Unit tests for `CashVarianceAlertService`.
/// Exercises threshold evaluation without a real network.
final class CashVarianceAlertServiceTests: XCTestCase {

    // MARK: - evaluateAndAlert (threshold logic only; mock API)

    func test_evaluateAndAlert_belowThreshold_returnsFalse() async throws {
        let api = MockAPIClientForVariance(shouldThrow: false)
        let sut = CashVarianceAlertService(api: api)

        // 200¢ variance, default threshold = 500¢ → no alert
        let fired = try await sut.evaluateAndAlert(
            varianceCents: 200,
            sessionId: 1,
            thresholdCents: 500
        )
        XCTAssertFalse(fired)
    }

    func test_evaluateAndAlert_atThreshold_returnsTrue() async throws {
        let api = MockAPIClientForVariance(shouldThrow: false)
        let sut = CashVarianceAlertService(api: api)

        // 500¢ variance, threshold = 500¢ → fires (≥)
        let fired = try await sut.evaluateAndAlert(
            varianceCents: 500,
            sessionId: 2,
            thresholdCents: 500
        )
        XCTAssertTrue(fired)
    }

    func test_evaluateAndAlert_negativeVariance_usesAbsoluteValue() async throws {
        let api = MockAPIClientForVariance(shouldThrow: false)
        let sut = CashVarianceAlertService(api: api)

        // −600¢ shortage, threshold = 500¢ → fires
        let fired = try await sut.evaluateAndAlert(
            varianceCents: -600,
            sessionId: 3,
            thresholdCents: 500
        )
        XCTAssertTrue(fired)
    }

    func test_evaluateAndAlert_serverUnavailable_doesNotThrow() async throws {
        let api = MockAPIClientForVariance(shouldThrow: true)
        let sut = CashVarianceAlertService(api: api)

        // Even when the server push fails gracefully, no throw propagates
        // (404/501 are absorbed by the actor).
        // The mock throws httpStatus(501) → actor returns false.
        let fired = try await sut.evaluateAndAlert(
            varianceCents: 1000,
            sessionId: 4,
            thresholdCents: 500
        )
        XCTAssertFalse(fired)
    }

    func test_defaultThreshold_is500Cents() {
        XCTAssertEqual(CashVarianceAlertService.defaultThresholdCents, 500)
    }
}

// MARK: - Minimal mock

private final class MockAPIClientForVariance: APIClient {

    let shouldThrow: Bool

    init(shouldThrow: Bool) {
        self.shouldThrow = shouldThrow
        super.init()
    }

    override func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        if shouldThrow {
            throw APITransportError.httpStatus(501, message: nil)
        }
        // Return a minimal success envelope
        let json = #"{"success":true}"#.data(using: .utf8)!
        return try JSONDecoder().decode(T.self, from: json)
    }

    override func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> T {
        // Return empty settings — no threshold configured
        let json = #"{"success":true,"data":{}}"#.data(using: .utf8)!
        return try JSONDecoder().decode(T.self, from: json)
    }
}
