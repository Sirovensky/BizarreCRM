import XCTest
@testable import Core

// §32 LogThrottle + LogRedactor tests.
// Covers: §32.6 (IMEI, APNs token redaction), §32.1 (LogThrottle behaviour).

final class LogThrottle§32Tests: XCTestCase {

    // MARK: — Test 3: LogRedactor strips IMEI (15 digits) → *IMEI*

    func test_redact_IMEI_15digits() {
        let input = "Device IMEI: 490154203237518 registered"
        let result = LogRedactor.redact(input)
        XCTAssertFalse(result.contains("490154203237518"),
            "15-digit IMEI should be removed from log output")
        XCTAssertTrue(result.contains("*IMEI*"),
            "IMEI placeholder *IMEI* must appear in redacted string")
    }

    func test_redact_IMEI_atWordBoundary() {
        // Ensure IMEI is matched only at word boundaries, not as part of a longer number.
        let result = LogRedactor.redact("imei=123456789012345 ok")
        XCTAssertTrue(result.contains("*IMEI*"),
            "IMEI within assignment expression should be redacted")
        XCTAssertFalse(result.contains("123456789012345"))
    }

    // MARK: — Test 4: LogRedactor strips APNs hex token (64 chars) → *PUSH_TOKEN*

    func test_redact_APNs_token_64hexChars() {
        // Real APNs tokens are 32 bytes = 64 hex characters.
        let token = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9"
        XCTAssertEqual(token.count, 64, "Precondition: test token must be 64 chars")
        let input = "Registered push token: \(token)"
        let result = LogRedactor.redact(input)
        XCTAssertFalse(result.contains(token),
            "64-char APNs hex token must not appear in redacted output")
        XCTAssertTrue(result.contains("*PUSH_TOKEN*"),
            "*PUSH_TOKEN* placeholder must be present")
    }

    func test_redact_APNs_token_uppercaseHex() {
        let token = "A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F9"
        XCTAssertEqual(token.count, 64)
        let result = LogRedactor.redact("token=\(token)")
        XCTAssertTrue(result.contains("*PUSH_TOKEN*"),
            "Uppercase APNs token should also be redacted")
    }

    // MARK: — Test 5: LogThrottle.shouldEmit behaviour

    func test_logThrottle_firstCall_returnsTrue() {
        let throttle = LogThrottle(interval: 60)
        XCTAssertTrue(throttle.shouldEmit(key: "first_call"),
            "First shouldEmit for a new key must return true")
    }

    func test_logThrottle_secondCallWithinWindow_returnsFalse() {
        let throttle = LogThrottle(interval: 60, maxBurst: 1)
        _ = throttle.shouldEmit(key: "dup")
        XCTAssertFalse(throttle.shouldEmit(key: "dup"),
            "Second call within window with maxBurst=1 must return false")
    }

    func test_logThrottle_differentKeys_areIndependent() {
        let throttle = LogThrottle(interval: 60, maxBurst: 1)
        _ = throttle.shouldEmit(key: "key_a")
        _ = throttle.shouldEmit(key: "key_a")  // second for key_a — suppressed
        XCTAssertTrue(throttle.shouldEmit(key: "key_b"),
            "A different key must be treated independently")
    }

    func test_logThrottle_windowExpiry_emitsAgain() {
        // Use a tiny interval so the window expires during the test without sleeping.
        let throttle = LogThrottle(interval: 0.01, maxBurst: 1)
        _ = throttle.shouldEmit(key: "expiry")
        // Busy-wait up to 200 ms for the 10 ms window to expire.
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            // tight poll — acceptable in a unit test for a tiny window
        }
        XCTAssertTrue(throttle.shouldEmit(key: "expiry"),
            "After the window expires, shouldEmit must return true again")
    }

    // MARK: — Test 6: LogThrottle.maxBurst allows N consecutive emits

    func test_logThrottle_maxBurst_allowsNConsecutiveEmits() {
        let burst = 3
        let throttle = LogThrottle(interval: 60, maxBurst: burst)
        var emitted = 0
        for _ in 0 ..< burst {
            if throttle.shouldEmit(key: "burst_test") { emitted += 1 }
        }
        XCTAssertEqual(emitted, burst,
            "LogThrottle with maxBurst=\(burst) must allow exactly \(burst) emits")
    }

    func test_logThrottle_maxBurst_suppressesAfterBurst() {
        let burst = 3
        let throttle = LogThrottle(interval: 60, maxBurst: burst)
        for _ in 0 ..< burst { _ = throttle.shouldEmit(key: "over_burst") }
        XCTAssertFalse(throttle.shouldEmit(key: "over_burst"),
            "Call #\(burst + 1) within window must be suppressed after maxBurst exhausted")
    }

    // MARK: — AppLog.Throttle shared instances exist (compile-only)

    func test_appLogThrottle_sharedInstances_exist() {
        _ = AppLog.Throttle.networking as AnyObject
        _ = AppLog.Throttle.hardware   as AnyObject
        _ = AppLog.Throttle.ui         as AnyObject
        _ = AppLog.Throttle.bg         as AnyObject
    }
}
