import Testing
import Foundation
@testable import RolesEditor

// MARK: - ElevationSessionTests

@Suite("ElevationSession")
struct ElevationSessionTests {

    // MARK: Basic grant / revoke

    @Test("elevate marks scope as elevated")
    func elevateGrantsScope() async {
        let session = ElevationSession(sessionDuration: 300)
        await session.elevate(scope: "invoices.refund")
        let elevated = await session.isElevated(for: "invoices.refund")
        #expect(elevated)
    }

    @Test("unelevated scope is not elevated")
    func unelevatedScopeReturnsFalse() async {
        let session = ElevationSession(sessionDuration: 300)
        let elevated = await session.isElevated(for: "invoices.refund")
        #expect(!elevated)
    }

    @Test("revoke removes scope")
    func revokeRemovesScope() async {
        let session = ElevationSession(sessionDuration: 300)
        await session.elevate(scope: "invoices.refund")
        await session.revoke(scope: "invoices.refund")
        let elevated = await session.isElevated(for: "invoices.refund")
        #expect(!elevated)
    }

    @Test("revokeAll removes all scopes")
    func revokeAllClearsAll() async {
        let session = ElevationSession(sessionDuration: 300)
        await session.elevate(scope: "invoices.refund")
        await session.elevate(scope: "tickets.delete")
        await session.revokeAll()
        let refund = await session.isElevated(for: "invoices.refund")
        let delete = await session.isElevated(for: "tickets.delete")
        #expect(!refund)
        #expect(!delete)
    }

    @Test("multiple independent scopes are tracked separately")
    func multipleScopes() async {
        let session = ElevationSession(sessionDuration: 300)
        await session.elevate(scope: "invoices.refund")
        let refundElevated = await session.isElevated(for: "invoices.refund")
        let deleteElevated = await session.isElevated(for: "tickets.delete")
        #expect(refundElevated)
        #expect(!deleteElevated)
    }

    // MARK: Expiry

    @Test("expired grant returns false")
    func expiredGrantReturnsFalse() async throws {
        let session = ElevationSession(sessionDuration: 0.01) // 10ms
        await session.elevate(scope: "invoices.refund")
        // Wait for expiry
        try await Task.sleep(for: .milliseconds(50))
        let elevated = await session.isElevated(for: "invoices.refund")
        #expect(!elevated)
    }

    @Test("remainingSeconds is positive for active grant")
    func remainingSecondsPositive() async {
        let session = ElevationSession(sessionDuration: 300)
        await session.elevate(scope: "test.scope")
        let remaining = await session.remainingSeconds(for: "test.scope")
        #expect((remaining ?? 0) > 0)
        #expect((remaining ?? 0) <= 300)
    }

    @Test("remainingSeconds returns nil for unelevated scope")
    func remainingSecondsNilForUnelevated() async {
        let session = ElevationSession(sessionDuration: 300)
        let remaining = await session.remainingSeconds(for: "nonexistent.scope")
        #expect(remaining == nil)
    }

    @Test("remainingSeconds returns nil after expiry")
    func remainingSecondsNilAfterExpiry() async throws {
        let session = ElevationSession(sessionDuration: 0.01)
        await session.elevate(scope: "test.scope")
        try await Task.sleep(for: .milliseconds(50))
        let remaining = await session.remainingSeconds(for: "test.scope")
        #expect(remaining == nil)
    }

    // MARK: 5-minute default

    @Test("default session duration is 5 minutes")
    func defaultDurationIsFiveMinutes() async {
        let session = ElevationSession()
        await session.elevate(scope: "test.scope")
        let remaining = await session.remainingSeconds(for: "test.scope")
        // Should be close to 300 seconds (within a second of test execution)
        #expect((remaining ?? 0) > 295)
    }

    // MARK: pruneExpired

    @Test("pruneExpired removes only expired grants")
    func pruneExpiredIsSelective() async throws {
        let session = ElevationSession(sessionDuration: 0.01)
        await session.elevate(scope: "short.scope")
        let session2 = ElevationSession(sessionDuration: 300)
        await session2.elevate(scope: "long.scope")

        try await Task.sleep(for: .milliseconds(50))

        await session.pruneExpired()
        await session2.pruneExpired()

        let short = await session.isElevated(for: "short.scope")
        let long = await session2.isElevated(for: "long.scope")

        #expect(!short)
        #expect(long)
    }
}
