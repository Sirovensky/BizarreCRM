import XCTest
@testable import Core

// §32 batch-2 tests — f09e7034
// Covers: LogRedactor §32.6 new patterns (*CARD_BIN*, *AUTH_CODE*, *ADDRESS*,
//         redactEmailBody, redactAddress), LoggingPolicy.LogLevel Comparable,
//         AnalyticsEvent typed helpers (loginSuccess/Failed, customerCreated,
//         ticketCreated, refundIssued), AppLog.payments + .location logger presence,
//         and NavigationPathScreenTracker compile-time existence.

final class Telemetry§32_b2Tests: XCTestCase {

    // MARK: — Test 1: CARD_BIN redaction

    /// §32.6 — "bin: 411111" labelled field must be replaced with *CARD_BIN*.
    func test_redact_cardBin_labelledField() {
        let input = "Processing bin: 411111 for transaction"
        let result = LogRedactor.redact(input)
        XCTAssertTrue(result.contains("*CARD_BIN*"),
            "Expected *CARD_BIN* token in redacted output; got: \(result)")
        XCTAssertFalse(result.contains("411111"),
            "Raw BIN digits must not appear in redacted output")
    }

    // MARK: — Test 2: AUTH_CODE redaction

    /// §32.6 — "otp: 123456" labelled OTP must be replaced with *AUTH_CODE*.
    func test_redact_authCode_otpLabel() {
        let input = "Verifying otp: 123456 for user"
        let result = LogRedactor.redact(input)
        XCTAssertTrue(result.contains("*AUTH_CODE*"),
            "Expected *AUTH_CODE* token in redacted output; got: \(result)")
        XCTAssertFalse(result.contains("123456"),
            "Raw OTP digits must not appear in redacted output")
    }

    /// §32.6 — "auth_code: 8675309" variant also triggers *AUTH_CODE*.
    func test_redact_authCode_authCodeLabel() {
        let input = "auth_code: 8675309 submitted"
        let result = LogRedactor.redact(input)
        XCTAssertTrue(result.contains("*AUTH_CODE*"),
            "auth_code: label must produce *AUTH_CODE* token; got: \(result)")
    }

    // MARK: — Test 3: LogLevel Comparable ordering

    /// §32.9 — debug < info < notice < error < fault must hold.
    func test_logLevel_comparableOrdering_fullChain() {
        typealias L = LoggingPolicy.LogLevel
        XCTAssertLessThan(L.debug,  L.info,   "debug must be less than info")
        XCTAssertLessThan(L.info,   L.notice, "info must be less than notice")
        XCTAssertLessThan(L.notice, L.error,  "notice must be less than error")
        XCTAssertLessThan(L.error,  L.fault,  "error must be less than fault")
    }

    /// §32.9 — allCases are in strictly ascending order.
    func test_logLevel_allCasesAscending() {
        let levels = LoggingPolicy.LogLevel.allCases
        for i in 0 ..< levels.count - 1 {
            XCTAssertLessThan(levels[i], levels[i + 1],
                "LogLevel.allCases[\(i)] must be less than [\(i+1)]")
        }
    }

    // MARK: — Test 4: AnalyticsEvent typed helpers raw-value verification

    /// §32.4 — trackLoginSuccess fires .loginSucceeded whose raw value is "auth.login.succeeded".
    func test_analyticsEvent_loginSucceeded_rawValue() {
        XCTAssertEqual(AnalyticsEvent.loginSucceeded.rawValue, "auth.login.succeeded",
            "loginSucceeded raw value must match §32.4 spec")
    }

    /// §32.4 — trackLoginFailed fires .loginFailed whose raw value is "auth.login.failed".
    func test_analyticsEvent_loginFailed_rawValue() {
        XCTAssertEqual(AnalyticsEvent.loginFailed.rawValue, "auth.login.failed",
            "loginFailed raw value must match §32.4 spec")
    }

    /// §32.4 — customerCreated raw value is "customer.created".
    func test_analyticsEvent_customerCreated_rawValue() {
        XCTAssertEqual(AnalyticsEvent.customerCreated.rawValue, "customer.created",
            "customerCreated raw value must match §32.4 spec")
    }

    /// §32.4 — ticketCreated raw value is "ticket.created".
    func test_analyticsEvent_ticketCreated_rawValue() {
        XCTAssertEqual(AnalyticsEvent.ticketCreated.rawValue, "ticket.created",
            "ticketCreated raw value must match §32.4 spec")
    }

    /// §32.4 — refundIssued raw value is "pos.refund.issued".
    func test_analyticsEvent_refundIssued_rawValue() {
        XCTAssertEqual(AnalyticsEvent.refundIssued.rawValue, "pos.refund.issued",
            "refundIssued raw value must match §32.4 spec")
    }

    // MARK: — Test 5: AppLog.payments + AppLog.location loggers exist (compile-only)

    /// §32 — payments and location Logger properties must be accessible.
    /// If either property does not exist the file will not compile.
    func test_appLog_paymentsAndLocation_loggers_exist() {
        _ = AppLog.payments as AnyObject
        _ = AppLog.location as AnyObject
    }

    // MARK: — Additional: redactEmailBody + redactAddress wrappers

    /// §32.6 — redactEmailBody returns *EMAIL_BODY* for non-empty input.
    func test_redactEmailBody_nonEmpty() {
        XCTAssertEqual(LogRedactor.redactEmailBody("Dear Customer, your invoice..."),
            "*EMAIL_BODY*",
            "redactEmailBody must return *EMAIL_BODY* for non-empty string")
    }

    /// §32.6 — redactEmailBody passes empty string through unchanged.
    func test_redactEmailBody_empty_passthrough() {
        XCTAssertEqual(LogRedactor.redactEmailBody(""), "",
            "redactEmailBody must not alter an empty string")
    }

    /// §32.6 — redactAddress returns *ADDRESS* for non-empty input.
    func test_redactAddress_nonEmpty() {
        XCTAssertEqual(LogRedactor.redactAddress("123 Main St, Springfield"),
            "*ADDRESS*",
            "redactAddress must return *ADDRESS* for non-empty string")
    }

    /// §32.6 — redactAddress passes empty string through unchanged.
    func test_redactAddress_empty_passthrough() {
        XCTAssertEqual(LogRedactor.redactAddress(""), "",
            "redactAddress must not alter an empty string")
    }

    // MARK: — Additional: ADDRESS regex rule strips street-shaped strings inline

    /// §32.6 — Inline address pattern "42 Elm Ave" in a log line must be replaced with *ADDRESS*.
    func test_redact_address_streetPattern_inLogLine() {
        let input = "Delivering to 42 Elm Ave per customer request"
        let result = LogRedactor.redact(input)
        XCTAssertTrue(result.contains("*ADDRESS*"),
            "Street-shaped address must be replaced by *ADDRESS* inline; got: \(result)")
    }
}
