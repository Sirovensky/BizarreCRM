import XCTest
import Networking
@testable import Pos

@MainActor
final class PosCustomerAttachTests: XCTestCase {

    func test_walkIn_sentinel_hasNilIdAndIsWalkInTrue() {
        let walkIn = PosCustomer.walkIn
        XCTAssertNil(walkIn.id)
        XCTAssertTrue(walkIn.isWalkIn)
        XCTAssertEqual(walkIn.displayName, "Walk-in")
    }

    func test_walkIn_initials_fallbackToW() {
        XCTAssertEqual(PosCustomer.walkIn.initials, "W")
    }

    func test_realCustomer_initialsFromName() {
        let c = PosCustomer(id: 42, displayName: "Ada Lovelace", email: "ada@example.com")
        XCTAssertFalse(c.isWalkIn)
        XCTAssertEqual(c.initials, "AL")
        XCTAssertEqual(c.id, 42)
        XCTAssertEqual(c.email, "ada@example.com")
    }

    func test_attachWalkIn_setsIsWalkInTrueAndHasCustomer() {
        let cart = Cart()
        cart.attach(customer: .walkIn)
        XCTAssertTrue(cart.customer?.isWalkIn ?? false)
        XCTAssertTrue(cart.hasCustomer)
    }

    func test_attachRealCustomer_setsIdAndDisplayName() {
        let cart = Cart()
        let ada = PosCustomer(id: 7, displayName: "Ada Lovelace", email: "ada@example.com", phone: "555-1212")
        cart.attach(customer: ada)
        XCTAssertEqual(cart.customer?.id, 7)
        XCTAssertEqual(cart.customer?.displayName, "Ada Lovelace")
        XCTAssertFalse(cart.customer?.isWalkIn ?? true)
    }

    func test_swapWalkInToReal_lastWriteWins() {
        let cart = Cart()
        cart.attach(customer: .walkIn)
        cart.attach(customer: PosCustomer(id: 3, displayName: "Grace Hopper"))
        XCTAssertEqual(cart.customer?.id, 3)
        XCTAssertFalse(cart.customer?.isWalkIn ?? true)
    }

    func test_swapRealToWalkIn_flipsToWalkIn() {
        let cart = Cart()
        cart.attach(customer: PosCustomer(id: 11, displayName: "Hedy Lamarr"))
        cart.attach(customer: .walkIn)
        XCTAssertNil(cart.customer?.id)
        XCTAssertTrue(cart.customer?.isWalkIn ?? false)
    }

    func test_detachCustomer_clearsCustomerButKeepsItems() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: Decimal(string: "9.99")!))
        cart.attach(customer: PosCustomer(id: 9, displayName: "Linus"))
        cart.detachCustomer()
        XCTAssertNil(cart.customer)
        XCTAssertEqual(cart.lineCount, 1, "detach must NOT drop line items")
    }

    func test_clear_clearsCustomerAndItems() {
        let cart = Cart()
        cart.add(CartItem(name: "A", unitPrice: 1))
        cart.attach(customer: PosCustomer(id: 1, displayName: "Alan Turing"))
        cart.clear()
        XCTAssertNil(cart.customer)
        XCTAssertTrue(cart.isEmpty)
    }

    #if canImport(UIKit)
    // `PosCustomerNameFormatter` + `PosCustomerMapper` live in files that
    // are gated on UIKit (the picker / chrome are iOS/iPad only). Guard
    // these tests the same way so the suite still compiles on macOS
    // hosts (`swift test`).
    func test_nameFormatter_joinsFirstAndLast() {
        XCTAssertEqual(
            PosCustomerNameFormatter.displayName(firstName: "Ada", lastName: "Lovelace"),
            "Ada Lovelace"
        )
    }

    func test_nameFormatter_fallsBackToOrganization() {
        XCTAssertEqual(
            PosCustomerNameFormatter.displayName(firstName: " ", lastName: "", fallback: "Acme"),
            "Acme"
        )
    }

    func test_attachPayload_usesMobileWhenPresent() {
        let p = PosCustomerNameFormatter.attachPayload(
            id: 42, firstName: "Ada", lastName: "Lovelace",
            email: "ada@x.co", phone: "111", mobile: "222", organization: ""
        )
        XCTAssertEqual(p.phone, "222", "mobile should win over phone")
        XCTAssertEqual(p.displayName, "Ada Lovelace")
    }

    func test_mapper_fromSummary() {
        let dict: [String: Any] = [
            "id": Int64(5),
            "first_name": "Ada",
            "last_name": "Lovelace",
            "email": "ada@x.co",
            "phone": "555"
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let summary = try! JSONDecoder().decode(CustomerSummary.self, from: data)
        let mapped = PosCustomerMapper.from(summary)
        XCTAssertEqual(mapped.id, 5)
        XCTAssertEqual(mapped.displayName, "Ada Lovelace")
        XCTAssertEqual(mapped.phone, "555")
    }
    #endif
}
