import XCTest
@testable import Core

// §32.6 — Canary tests. Well-known PII-shaped strings must NEVER appear
// verbatim in a serialized telemetry payload after passing through
// `LogRedactor` or `AnalyticsRedactor`. If any of these escapes, redaction
// has regressed and CI must fail.
final class Telemetry_32_6_CanaryTests: XCTestCase {

    // Canary inputs covering placeholders listed in the §32.6 redaction table.
    private let canaries: [String] = [
        "user@example.com",
        "(555) 123-4567",
        "+1 (555) 867-5309",
        "555-123-4567",
        "4111 1111 1111 1111",          // PAN shape
        "Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig",
        "passcode: 123456",
        "otp: 654321",
        "serial: ABCDE1234567",
        "123456789012345"                // IMEI shape
    ]

    // MARK: — LogRedactor.redact

    func test_canaries_neverAppearInRedactedString() {
        for canary in canaries {
            let input = "before \(canary) after"
            let redacted = LogRedactor.redact(input)
            XCTAssertFalse(
                redacted.contains(canary),
                "Canary '\(canary)' leaked through LogRedactor: '\(redacted)'"
            )
        }
    }

    func test_atSignTokenNeverSurvivesRedaction() {
        let inputs = [
            "from a@b.com to c@d.org",
            "Reach me at someone@somewhere.io please",
            "log: parsed user=admin@corp.example"
        ]
        for input in inputs {
            let redacted = LogRedactor.redact(input)
            XCTAssertFalse(
                redacted.contains("@"),
                "@-bearing token survived redaction: '\(redacted)'"
            )
        }
    }

    func test_phoneShape_neverSurvivesRedaction() {
        let phones = ["5551234567", "555-123-4567", "(555) 123-4567"]
        for raw in phones {
            let redacted = LogRedactor.redact("call \(raw) tomorrow")
            XCTAssertFalse(
                redacted.contains(raw),
                "Phone '\(raw)' leaked through redaction: '\(redacted)'"
            )
        }
    }

    func test_atExampleCom_canaryNeverAppearsInRedactedString() {
        // §32.6 explicitly calls out '@example.com' as a canary that must
        // never serialize. (The 555-1212 7-digit canary needs an extended
        // local-format rule before it can be asserted; tracked separately.)
        let redacted = LogRedactor.redact("payload contains user@example.com somewhere")
        XCTAssertFalse(
            redacted.contains("@example.com"),
            "Literal canary '@example.com' leaked: '\(redacted)'"
        )
    }

    // MARK: — AnalyticsRedactor

    func test_analyticsRedactor_dropsPiiKeyedProperties() {
        let props: [String: AnalyticsValue] = [
            "duration_ms": .int(1234),
            "email": .string("leak@example.com"),
            "phone": .string("555-1212")
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertNotNil(scrubbed["duration_ms"])
        XCTAssertNil(scrubbed["email"], "PII-keyed property should be dropped")
        XCTAssertNil(scrubbed["phone"], "PII-keyed property should be dropped")
    }

    func test_analyticsRedactor_redactsEmailEmbeddedInString() {
        let props: [String: AnalyticsValue] = [
            "reason": .string("server told me john@example.com failed")
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        guard case let .string(val) = scrubbed["reason"] else {
            return XCTFail("reason should be present after scrub")
        }
        XCTAssertFalse(val.contains("@"), "email survived scrub: '\(val)'")
        XCTAssertFalse(val.contains("john@example.com"))
    }

    func test_analyticsRedactor_preservesNumericAndBoolValues() {
        let props: [String: AnalyticsValue] = [
            "count": .int(7),
            "ratio": .double(0.42),
            "ok":    .bool(true)
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertEqual(scrubbed.count, 3, "non-string non-PII values must pass through")
    }
}
