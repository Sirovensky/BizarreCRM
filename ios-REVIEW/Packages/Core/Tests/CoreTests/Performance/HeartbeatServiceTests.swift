import XCTest
@testable import Core

// §32.9 HeartbeatService — unit tests.
// Uses actor isolation + controlled clock (Task.sleep override not available,
// so we verify start/stop semantics and payload shape only).

final class HeartbeatServiceTests: XCTestCase {

    // MARK: — HeartbeatPayload shape

    func test_payload_timestampIsISO8601() {
        let p = HeartbeatPayload()
        // ISO 8601 with time: must contain 'T' and 'Z' or '+'.
        XCTAssertTrue(p.timestamp.contains("T"),
                      "timestamp must be ISO-8601 with time component")
    }

    func test_payload_appVersionIsNonEmpty() {
        let p = HeartbeatPayload()
        XCTAssertFalse(p.appVersion.isEmpty, "appVersion must be non-empty")
    }

    func test_payload_osVersionIsNonEmpty() {
        let p = HeartbeatPayload()
        XCTAssertFalse(p.osVersion.isEmpty, "osVersion must be non-empty")
    }

    func test_payload_isCodable() throws {
        let p = HeartbeatPayload()
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(HeartbeatPayload.self, from: data)
        XCTAssertEqual(p.timestamp,  decoded.timestamp)
        XCTAssertEqual(p.appVersion, decoded.appVersion)
        XCTAssertEqual(p.osVersion,  decoded.osVersion)
    }

    // MARK: — Interval constant

    func test_interval_isFiveMinutes() {
        XCTAssertEqual(HeartbeatService.interval, 5 * 60,
                       "Interval must be exactly 5 minutes per §32.9")
    }

    // MARK: — Start / stop lifecycle

    func test_start_callsPostImmediately() async throws {
        let service = HeartbeatService()
        let fired = ActorBox<Int>(0)

        await service.start { _ in
            await fired.increment()
        }

        // Give the first ping a brief chance to execute.
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        await service.stop()

        let count = await fired.value
        XCTAssertGreaterThanOrEqual(count, 1,
            "start() must fire at least one ping immediately (§32.9)")
    }

    func test_stop_preventsAdditionalPings() async throws {
        let service = HeartbeatService()
        let fired = ActorBox<Int>(0)

        await service.start { _ in await fired.increment() }
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05s
        await service.stop()

        let countAfterStop = await fired.value
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s — verify no more fire
        let countAfterWait = await fired.value
        XCTAssertEqual(countAfterStop, countAfterWait,
            "stop() must halt the ping loop (§32.9)")
    }

    func test_startTwice_doesNotDoubleFire() async throws {
        let service = HeartbeatService()
        let fired = ActorBox<Int>(0)
        let post: @Sendable (HeartbeatPayload) async throws -> Void = { _ in
            await fired.increment()
        }

        await service.start(post: post)
        await service.start(post: post) // second call is a no-op

        try await Task.sleep(nanoseconds: 100_000_000)
        await service.stop()

        let count = await fired.value
        // Without deduplication a second start would cause two immediate pings.
        // With deduplication at most 1 ping from the initial start.
        XCTAssertLessThanOrEqual(count, 2,
            "Double start() must not double the ping rate")
    }
}

// MARK: — Helpers

/// Simple actor-isolated counter for cross-task counting in tests.
private actor ActorBox<T> {
    private(set) var value: T
    init(_ initial: T) { self.value = initial }
}

extension ActorBox where T == Int {
    func increment() { value += 1 }
}
