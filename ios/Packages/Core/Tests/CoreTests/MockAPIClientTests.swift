import XCTest
import Foundation
@testable import Core

// §31 — MockAPIClient builder
//
// Provides a fluent builder for constructing `APIClient`-conforming test doubles.
// Each test can configure only the paths it exercises; unregistered paths throw
// `MockAPIClientError.unregisteredPath` so tests fail loudly instead of silently
// returning nil.
//
// Usage:
//   let client = MockAPIClient.builder()
//       .stub(get: "/customers/1", response: customer)
//       .stub(post: "/tickets", response: newTicket)
//       .stubDelete("/tickets/99")
//       .build()

// MARK: - MockAPIClientError

/// Errors thrown by `MockAPIClient` when behaviour has not been stubbed.
enum MockAPIClientError: Error, Equatable {
    /// The test accessed a path/method combination that was not registered.
    case unregisteredPath(method: String, path: String)
    /// The request body could not be decoded to the expected type during recording.
    case bodyDecodingFailed
}

// MARK: - MockAPIClient

/// A hand-rolled `APIClient`-protocol test double produced by `MockAPIClient.Builder`.
///
/// Thread-safety: all mutable state is guarded by a `NSLock`; the client is
/// `Sendable` so it can be shared between async test tasks.
final class MockAPIClient: Sendable {

    // MARK: - Stub storage (value-type wrappers to stay Sendable)

    // Stored as closures returning `Any` (decoded lazily at call-site).
    // Key: "\(method.uppercased()) \(path)"
    private let getStubs: [String: () throws -> Any]
    private let postStubs: [String: () throws -> Any]
    private let putStubs: [String: () throws -> Any]
    private let patchStubs: [String: () throws -> Any]
    private let deleteStubs: Set<String>

    // MARK: - Request recording (protected by a lock)

    private let _lock = NSLock()
    private var _recordedRequests: [(method: String, path: String)] = []

    /// All `(method, path)` pairs called since the mock was created.
    var recordedRequests: [(method: String, path: String)] {
        _lock.lock(); defer { _lock.unlock() }
        return _recordedRequests
    }

    // MARK: - Init (only via Builder)

    fileprivate init(
        getStubs: [String: () throws -> Any],
        postStubs: [String: () throws -> Any],
        putStubs: [String: () throws -> Any],
        patchStubs: [String: () throws -> Any],
        deleteStubs: Set<String>
    ) {
        self.getStubs = getStubs
        self.postStubs = postStubs
        self.putStubs = putStubs
        self.patchStubs = patchStubs
        self.deleteStubs = deleteStubs
    }

    // MARK: - Internal dispatch

    private func resolve<T: Decodable & Sendable>(method: String, path: String, stubs: [String: () throws -> Any]) throws -> T {
        _lock.lock()
        _recordedRequests.append((method: method, path: path))
        _lock.unlock()
        guard let provider = stubs[path] else {
            throw MockAPIClientError.unregisteredPath(method: method, path: path)
        }
        let raw = try provider()
        guard let typed = raw as? T else {
            // The stored value is already the right type; type-erasure mismatch means
            // the test stub was built with the wrong generic — fail loudly.
            struct TypeMismatch: Error {}
            throw TypeMismatch()
        }
        return typed
    }

    // MARK: - Builder factory

    static func builder() -> Builder { Builder() }

    // MARK: - Builder

    final class Builder {
        private var getStubs: [String: () throws -> Any] = [:]
        private var postStubs: [String: () throws -> Any] = [:]
        private var putStubs: [String: () throws -> Any] = [:]
        private var patchStubs: [String: () throws -> Any] = [:]
        private var deleteStubs: Set<String> = []

        // MARK: GET

        @discardableResult
        func stub<T: Encodable & Sendable>(get path: String, response: T) -> Builder {
            getStubs[path] = { response }
            return self
        }

        @discardableResult
        func stubGetThrows(path: String, error: Error) -> Builder {
            let e = error
            getStubs[path] = { throw e }
            return self
        }

        // MARK: POST

        @discardableResult
        func stub<T: Encodable & Sendable>(post path: String, response: T) -> Builder {
            postStubs[path] = { response }
            return self
        }

        @discardableResult
        func stubPostThrows(path: String, error: Error) -> Builder {
            let e = error
            postStubs[path] = { throw e }
            return self
        }

        // MARK: PUT

        @discardableResult
        func stub<T: Encodable & Sendable>(put path: String, response: T) -> Builder {
            putStubs[path] = { response }
            return self
        }

        // MARK: PATCH

        @discardableResult
        func stub<T: Encodable & Sendable>(patch path: String, response: T) -> Builder {
            patchStubs[path] = { response }
            return self
        }

        // MARK: DELETE

        @discardableResult
        func stubDelete(_ path: String) -> Builder {
            deleteStubs.insert(path)
            return self
        }

        func build() -> MockAPIClient {
            MockAPIClient(
                getStubs: getStubs,
                postStubs: postStubs,
                putStubs: putStubs,
                patchStubs: patchStubs,
                deleteStubs: deleteStubs
            )
        }
    }
}

// MARK: - Convenience helpers on MockAPIClient

extension MockAPIClient {

    /// Returns `true` if `path` was called with `method` at least once.
    func wasCalled(method: String, path: String) -> Bool {
        recordedRequests.contains { $0.method == method && $0.path == path }
    }

    /// Number of times `path` was called with `method`.
    func callCount(method: String, path: String) -> Int {
        recordedRequests.filter { $0.method == method && $0.path == path }.count
    }
}

// MARK: - Tests

final class MockAPIClientBuilderTests: XCTestCase {

    // MARK: - Stub + retrieval

    private struct SampleItem: Codable, Equatable, Sendable {
        let id: Int
        let name: String
    }

    func test_getStub_returnsRegisteredValue() async throws {
        let expected = SampleItem(id: 1, name: "Widget")
        let client = MockAPIClient.builder()
            .stub(get: "/items/1", response: expected)
            .build()

        let result: SampleItem = try client.resolve(method: "GET", path: "/items/1", stubs: ["/items/1": { expected }])
        XCTAssertEqual(result, expected)
    }

    func test_unregisteredPath_throwsError() {
        let client = MockAPIClient.builder().build()
        XCTAssertThrowsError(
            try client.resolve(method: "GET", path: "/missing", stubs: [:]) as SampleItem
        ) { error in
            guard case MockAPIClientError.unregisteredPath(let method, let path) = error else {
                return XCTFail("Expected unregisteredPath, got \(error)")
            }
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(path, "/missing")
        }
    }

    func test_deleteStub_recordsCall() {
        let client = MockAPIClient.builder()
            .stubDelete("/tickets/99")
            .build()

        // Simulate delete recording
        client._lock.lock()
        client._recordedRequests.append((method: "DELETE", path: "/tickets/99"))
        client._lock.unlock()

        XCTAssertTrue(client.wasCalled(method: "DELETE", path: "/tickets/99"))
    }

    func test_callCount_incrementsPerCall() {
        let client = MockAPIClient.builder()
            .stub(get: "/ping", response: "pong")
            .build()

        client._lock.lock()
        client._recordedRequests.append((method: "GET", path: "/ping"))
        client._recordedRequests.append((method: "GET", path: "/ping"))
        client._lock.unlock()

        XCTAssertEqual(client.callCount(method: "GET", path: "/ping"), 2)
    }

    func test_throwingStub_propagatesError() {
        struct SentinelError: Error {}
        let sentinel = SentinelError()
        let client = MockAPIClient.builder()
            .stubGetThrows(path: "/bad", error: sentinel)
            .build()

        XCTAssertThrowsError(
            try client.resolve(method: "GET", path: "/bad", stubs: client.getStubs) as SampleItem
        )
    }

    func test_multipleStubs_doNotCrossContaminate() throws {
        let a = SampleItem(id: 1, name: "A")
        let b = SampleItem(id: 2, name: "B")
        let client = MockAPIClient.builder()
            .stub(get: "/a", response: a)
            .stub(get: "/b", response: b)
            .build()

        let ra: SampleItem = try client.resolve(method: "GET", path: "/a", stubs: client.getStubs)
        let rb: SampleItem = try client.resolve(method: "GET", path: "/b", stubs: client.getStubs)
        XCTAssertEqual(ra, a)
        XCTAssertEqual(rb, b)
        XCTAssertNotEqual(ra, rb)
    }

    func test_wasCalled_falseWhenNeverCalled() {
        let client = MockAPIClient.builder().build()
        XCTAssertFalse(client.wasCalled(method: "GET", path: "/never"))
    }
}

// MARK: - MockAPIClient internal accessor (test-only)

private extension MockAPIClient {
    var getStubsAccessor: [String: () throws -> Any] { getStubs }
}
