import XCTest
@testable import Camera

/// Tests that every ``CameraError`` case has a non-empty `errorDescription`.
///
/// Any case added to the enum without a matching `errorDescription` branch will
/// cause `test_allCases_haveErrorDescription` to fail at compile time (exhaustive
/// switch) — the individual per-case tests provide precise failure messages.
final class CameraErrorTests: XCTestCase {

    // MARK: - notAuthorized

    func test_notAuthorized_errorDescription_isNonEmpty() {
        let error = CameraError.notAuthorized
        XCTAssertFalse(
            (error.errorDescription ?? "").isEmpty,
            "notAuthorized must have a non-empty errorDescription"
        )
    }

    func test_notAuthorized_errorDescription_mentionsSettings() {
        let description = CameraError.notAuthorized.errorDescription ?? ""
        XCTAssertTrue(
            description.localizedCaseInsensitiveContains("settings"),
            "notAuthorized description should direct users to Settings; got: \(description)"
        )
    }

    // MARK: - hardwareUnavailable

    func test_hardwareUnavailable_errorDescription_isNonEmpty() {
        let error = CameraError.hardwareUnavailable
        XCTAssertFalse(
            (error.errorDescription ?? "").isEmpty,
            "hardwareUnavailable must have a non-empty errorDescription"
        )
    }

    // MARK: - captureFailed

    func test_captureFailed_errorDescription_containsReason() {
        let reason = "sensor overheated"
        let error = CameraError.captureFailed(reason)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(
            description.contains(reason),
            "captureFailed description must embed the reason; got: \(description)"
        )
    }

    func test_captureFailed_emptyReason_errorDescription_isNonEmpty() {
        let error = CameraError.captureFailed("")
        XCTAssertFalse(
            (error.errorDescription ?? "").isEmpty,
            "captureFailed with empty reason must still have a non-empty errorDescription"
        )
    }

    // MARK: - Exhaustive case coverage

    func test_allCasesAreHandledByLocalizedError() {
        // Force an exhaustive switch so new cases added without errorDescription
        // produce a compile-time error rather than a silent test gap.
        let cases: [CameraError] = [
            .notAuthorized,
            .hardwareUnavailable,
            .captureFailed("test")
        ]
        for c in cases {
            switch c {
            case .notAuthorized:
                XCTAssertNotNil(c.errorDescription)
            case .hardwareUnavailable:
                XCTAssertNotNil(c.errorDescription)
            case .captureFailed:
                XCTAssertNotNil(c.errorDescription)
            }
        }
    }
}
