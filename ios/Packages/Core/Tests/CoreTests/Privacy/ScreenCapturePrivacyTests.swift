import XCTest
@testable import Core

// §28 Security & Privacy helpers — ScreenCapturePrivacy publisher tests
//
// Real UIScreen state cannot be toggled in unit tests; all tests use
// MockScreenCapturePrivacy which provides direct isCaptured mutation.

final class ScreenCapturePrivacyTests: XCTestCase {

    // MARK: - MockScreenCapturePrivacy — initial state

    func test_mock_defaultsToNotCaptured() {
        let mock = MockScreenCapturePrivacy()
        XCTAssertFalse(mock.isCaptured)
    }

    func test_mock_initialValueHonoured() {
        let mock = MockScreenCapturePrivacy(isCaptured: true)
        XCTAssertTrue(mock.isCaptured)
    }

    // MARK: - MockScreenCapturePrivacy — state mutation

    func test_mock_isCaptured_canBeSetToTrue() {
        let mock = MockScreenCapturePrivacy()
        mock.isCaptured = true
        XCTAssertTrue(mock.isCaptured)
    }

    func test_mock_isCaptured_canBeSetToFalse() {
        let mock = MockScreenCapturePrivacy(isCaptured: true)
        mock.isCaptured = false
        XCTAssertFalse(mock.isCaptured)
    }

    func test_mock_simulateCaptureChange_updatesState() {
        let mock = MockScreenCapturePrivacy()
        mock.simulateCaptureChange(isCaptured: true)
        XCTAssertTrue(mock.isCaptured)
        mock.simulateCaptureChange(isCaptured: false)
        XCTAssertFalse(mock.isCaptured)
    }

    // MARK: - Protocol conformance

    func test_mock_conformsToProtocol() {
        let service: ScreenCapturePrivacyProtocol = MockScreenCapturePrivacy()
        XCTAssertFalse(service.isCaptured)
    }

    func test_mock_conformsToProtocol_capturedTrue() {
        let service: ScreenCapturePrivacyProtocol = MockScreenCapturePrivacy(isCaptured: true)
        XCTAssertTrue(service.isCaptured)
    }

    // MARK: - Blurring decision helper (view model pattern)

    /// Simulates the decision logic a view would use.
    func test_viewShouldBlur_whenCaptured() {
        let service: ScreenCapturePrivacyProtocol = MockScreenCapturePrivacy(isCaptured: true)
        let shouldBlur = service.isCaptured
        XCTAssertTrue(shouldBlur)
    }

    func test_viewShouldNotBlur_whenNotCaptured() {
        let service: ScreenCapturePrivacyProtocol = MockScreenCapturePrivacy(isCaptured: false)
        let shouldBlur = service.isCaptured
        XCTAssertFalse(shouldBlur)
    }

    // MARK: - Multiple rapid toggles

    func test_rapidToggles_maintainCorrectFinalState() {
        let mock = MockScreenCapturePrivacy()
        for i in 0..<10 {
            mock.simulateCaptureChange(isCaptured: i % 2 == 0)
        }
        // After 10 iterations (0..9), the last call is i=9 (odd) → isCaptured = false
        XCTAssertFalse(mock.isCaptured)
    }
}
