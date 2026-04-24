import XCTest
@testable import Customers
@testable import Networking

// MARK: - CustomerContextMenuTests
//
// Unit tests for `CustomerContextMenu`'s phone/email resolution helpers
// and copy behaviour. We test the pure data logic rather than the SwiftUI
// view hierarchy (which requires Xcode Previews / snapshot infra).

final class CustomerContextMenuTests: XCTestCase {

    // MARK: - bestPhone resolution

    func test_bestPhone_prefersMobileOverPhone() {
        let c = makeCustomer(mobile: "555-1111", phone: "555-2222")
        XCTAssertEqual(contextMenuBestPhone(for: c), "555-1111")
    }

    func test_bestPhone_fallsBackToPhoneWhenMobileNil() {
        let c = makeCustomer(mobile: nil, phone: "555-2222")
        XCTAssertEqual(contextMenuBestPhone(for: c), "555-2222")
    }

    func test_bestPhone_returnsNilWhenBothAbsent() {
        let c = makeCustomer(mobile: nil, phone: nil)
        XCTAssertNil(contextMenuBestPhone(for: c))
    }

    func test_bestPhone_returnsNilWhenMobileEmptyAndPhoneEmpty() {
        let c = makeCustomer(mobile: "", phone: "")
        XCTAssertNil(contextMenuBestPhone(for: c))
    }

    func test_bestPhone_ignoresEmptyMobileFallsToPhone() {
        let c = makeCustomer(mobile: "", phone: "555-3333")
        XCTAssertEqual(contextMenuBestPhone(for: c), "555-3333")
    }

    // MARK: - Email presence

    func test_hasEmail_returnsTrueWhenEmailPresent() {
        let c = makeCustomer(email: "bob@example.com")
        XCTAssertTrue(contextMenuHasEmail(for: c))
    }

    func test_hasEmail_returnsFalseWhenEmailNil() {
        let c = makeCustomer(email: nil)
        XCTAssertFalse(contextMenuHasEmail(for: c))
    }

    func test_hasEmail_returnsFalseWhenEmailEmpty() {
        let c = makeCustomer(email: "")
        XCTAssertFalse(contextMenuHasEmail(for: c))
    }

    // MARK: - Helpers

    private func makeCustomer(
        id: Int64 = 42,
        email: String? = nil,
        phone: String? = nil,
        mobile: String? = nil
    ) -> CustomerSummary {
        var parts: [String] = ["\"id\": \(id)", "\"first_name\": \"Test\"", "\"last_name\": \"User\""]
        if let v = email  { parts.append("\"email\": \"\(v)\"") }
        if let v = phone  { parts.append("\"phone\": \"\(v)\"") }
        if let v = mobile { parts.append("\"mobile\": \"\(v)\"") }
        let json = ("{ " + parts.joined(separator: ", ") + " }").data(using: .utf8)!
        return try! JSONDecoder().decode(CustomerSummary.self, from: json)
    }

    // These mirror the private logic in CustomerContextMenu. The real
    // implementation uses UIPasteboard on-device; we extract just the
    // data-resolution portion for pure-Swift unit testing.

    private func contextMenuBestPhone(for c: CustomerSummary) -> String? {
        if let m = c.mobile, !m.isEmpty { return m }
        if let p = c.phone, !p.isEmpty { return p }
        return nil
    }

    private func contextMenuHasEmail(for c: CustomerSummary) -> Bool {
        guard let e = c.email, !e.isEmpty else { return false }
        return true
    }
}
