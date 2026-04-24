import XCTest
import CryptoKit
@testable import Networking

// MARK: - PinningStoreTests
//
// Unit tests for PinningStore actor (§1.2 TLS Pinning).
// Coverage target: ≥ 80% of PinningStore.swift
//
// Each test uses a unique keychainService string to isolate Keychain entries
// and avoid cross-test pollution.

final class PinningStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore(suffix: String = #function) -> PinningStore {
        // Unique service name per test avoids Keychain cross-contamination.
        PinningStore(keychainService: "com.bizarrecrm.pinning.test.\(suffix)")
    }

    private func baseURL(_ s: String = "https://tenant.example.com") -> URL {
        URL(string: s)!
    }

    private func pin(_ seed: UInt8) -> Data {
        Data(SHA256.hash(data: Data(repeating: seed, count: 16)))
    }

    // MARK: - In-memory policy round-trip

    func testSetAndGetInMemoryPolicy() async {
        let store = makeStore()
        let policy = PinningPolicy(pins: [pin(1)], failClosed: true)
        await store.setPolicyInMemory(policy, for: baseURL())
        let resolved = await store.policy(for: baseURL())
        XCTAssertEqual(resolved, policy)
    }

    func testRemoveInMemoryPolicyFallsBackToNoPinning() async {
        let store = makeStore()
        let policy = PinningPolicy(pins: [pin(2)], failClosed: true)
        await store.setPolicyInMemory(policy, for: baseURL())
        await store.removePolicyInMemory(for: baseURL())
        let resolved = await store.policy(for: baseURL())
        XCTAssertEqual(resolved, .noPinning)
    }

    func testNoPolicySetReturnsNoPinning() async {
        let store = makeStore()
        let resolved = await store.policy(for: baseURL())
        XCTAssertEqual(resolved, .noPinning)
    }

    // MARK: - URL key canonicalization

    func testTrailingSlashNormalized() async {
        let store = makeStore()
        let policy = PinningPolicy(pins: [pin(3)], failClosed: true)
        await store.setPolicyInMemory(policy, for: URL(string: "https://tenant.example.com/")!)
        let resolved = await store.policy(for: URL(string: "https://tenant.example.com")!)
        XCTAssertEqual(resolved.pins, policy.pins)
    }

    func testCaseNormalization() async {
        let store = makeStore()
        let policy = PinningPolicy(pins: [pin(4)], failClosed: true)
        await store.setPolicyInMemory(policy, for: URL(string: "HTTPS://TENANT.EXAMPLE.COM")!)
        let resolved = await store.policy(for: URL(string: "https://tenant.example.com")!)
        XCTAssertEqual(resolved.pins, policy.pins)
    }

    // MARK: - Keychain persistence

    func testPersistAndRetrievePolicy() async throws {
        let store = makeStore()
        let p = PinningPolicy(pins: [pin(5)], allowBackupIfPinsEmpty: false, failClosed: true)
        try await store.persistPolicy(p, for: baseURL())
        // Retrieve from a fresh store sharing the same Keychain service.
        let store2 = PinningStore(keychainService: "com.bizarrecrm.pinning.test.\(#function)")
        let resolved = await store2.policy(for: baseURL())
        XCTAssertEqual(resolved.pins, p.pins)
        XCTAssertEqual(resolved.allowBackupIfPinsEmpty, p.allowBackupIfPinsEmpty)
        XCTAssertEqual(resolved.failClosed, p.failClosed)
    }

    func testPersistOverwritesPreviousPolicy() async throws {
        let store = makeStore()
        let url = baseURL()
        let first = PinningPolicy(pins: [pin(6)], failClosed: true)
        let second = PinningPolicy(pins: [pin(7)], failClosed: false)
        try await store.persistPolicy(first, for: url)
        try await store.persistPolicy(second, for: url)
        let resolved = await store.policy(for: url)
        XCTAssertFalse(resolved.pins.contains(pin(6)), "Old pin should not survive overwrite")
        XCTAssertTrue(resolved.pins.contains(pin(7)))
    }

    func testRemovePersistedPolicySucceeds() async throws {
        let store = makeStore()
        let url = baseURL()
        let p = PinningPolicy(pins: [pin(8)], failClosed: true)
        try await store.persistPolicy(p, for: url)
        try await store.removePersistedPolicy(for: url)
        let store2 = PinningStore(keychainService: "com.bizarrecrm.pinning.test.\(#function)")
        let resolved = await store2.policy(for: url)
        XCTAssertEqual(resolved, .noPinning)
    }

    func testRemoveNonExistentPersistedPolicyDoesNotThrow() async {
        let store = makeStore()
        // Should not throw when there is nothing to delete.
        do {
            try await store.removePersistedPolicy(for: baseURL("https://unknown.example.com"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Policy merging

    func testInMemoryAndPersistedPinsAreMerged() async throws {
        let store = makeStore()
        let url = baseURL()
        let memPin = pin(9)
        let keychainPin = pin(10)

        let inMemPolicy = PinningPolicy(pins: [memPin], allowBackupIfPinsEmpty: true, failClosed: true)
        await store.setPolicyInMemory(inMemPolicy, for: url)
        // Write only the keychain pin via a second store sharing the same service.
        let writer = PinningStore(keychainService: "com.bizarrecrm.pinning.test.\(#function)")
        try await writer.persistPolicy(
            PinningPolicy(pins: [keychainPin], allowBackupIfPinsEmpty: false, failClosed: false),
            for: url
        )

        // Re-read from the original store that has the in-memory entry.
        let store3 = PinningStore(keychainService: "com.bizarrecrm.pinning.test.\(#function)")
        await store3.setPolicyInMemory(inMemPolicy, for: url)
        let resolved = await store3.policy(for: url)

        // Both pins must be present.
        XCTAssertTrue(resolved.pins.contains(memPin))
        XCTAssertTrue(resolved.pins.contains(keychainPin))
        // Flags come from the in-memory policy.
        XCTAssertTrue(resolved.failClosed)
        XCTAssertTrue(resolved.allowBackupIfPinsEmpty)
    }

    // MARK: - Empty pins: allowBackupIfPinsEmpty logic

    func testEmptyPinsWithAllowBackupResolvesToNoPinning() async {
        let store = makeStore()
        let policy = PinningPolicy(pins: [], allowBackupIfPinsEmpty: true, failClosed: false)
        await store.setPolicyInMemory(policy, for: baseURL())
        let resolved = await store.policy(for: baseURL())
        XCTAssertTrue(resolved.pins.isEmpty)
        XCTAssertTrue(resolved.allowBackupIfPinsEmpty)
    }

    func testEmptyPinsWithoutBackupResolves() async {
        let store = makeStore()
        let policy = PinningPolicy(pins: [], allowBackupIfPinsEmpty: false, failClosed: true)
        await store.setPolicyInMemory(policy, for: baseURL())
        let resolved = await store.policy(for: baseURL())
        XCTAssertTrue(resolved.pins.isEmpty)
        XCTAssertFalse(resolved.allowBackupIfPinsEmpty)
        XCTAssertTrue(resolved.failClosed)
    }
}
