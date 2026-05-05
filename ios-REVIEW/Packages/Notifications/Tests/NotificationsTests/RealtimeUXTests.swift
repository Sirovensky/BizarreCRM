import XCTest
@testable import Notifications

// MARK: - §21.7 Real-time UX tests

final class RealtimeUXTests: XCTestCase {

    // MARK: - WSToast model

    func test_wsToast_hasUniqueIds() {
        let a = WSToast(message: "New message from Alice")
        let b = WSToast(message: "New message from Bob")
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_wsToast_defaultSystemImage() {
        let toast = WSToast(message: "Test")
        XCTAssertEqual(toast.systemImage, "bell.fill")
    }

    func test_wsToast_customSystemImage() {
        let toast = WSToast(message: "SMS", systemImage: "message.fill", deepLink: "bizarrecrm://sms/1")
        XCTAssertEqual(toast.systemImage, "message.fill")
        XCTAssertEqual(toast.deepLink, "bizarrecrm://sms/1")
    }

    func test_wsToast_equality() {
        let id = UUID()
        let a = WSToast(id: id, message: "Test", systemImage: "bell", deepLink: nil)
        let b = WSToast(id: id, message: "Test", systemImage: "bell", deepLink: nil)
        XCTAssertEqual(a, b)
    }

    func test_wsToast_deepLink_isOptional() {
        let toast = WSToast(message: "No deep link")
        XCTAssertNil(toast.deepLink)
    }
}
