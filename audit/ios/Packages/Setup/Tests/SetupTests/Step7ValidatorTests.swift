import XCTest
@testable import Setup

final class Step7ValidatorTests: XCTestCase {

    // MARK: - isNextEnabled

    func testIsNextEnabled_cashOnly_returnsTrue() {
        XCTAssertTrue(Step7Validator.isNextEnabled(methods: [.cash]))
    }

    func testIsNextEnabled_emptySet_returnsFalse() {
        XCTAssertFalse(Step7Validator.isNextEnabled(methods: []))
    }

    func testIsNextEnabled_multipleMethodsEnabled_returnsTrue() {
        XCTAssertTrue(Step7Validator.isNextEnabled(methods: [.cash, .card, .giftCard]))
    }

    // MARK: - validate

    func testValidate_singleMethod_isValid() {
        let result = Step7Validator.validate(methods: [.card])
        XCTAssertTrue(result.isValid)
    }

    func testValidate_emptySet_isInvalid() {
        let result = Step7Validator.validate(methods: [])
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidate_allMethods_isValid() {
        let all = Set(PaymentMethod.allCases)
        XCTAssertTrue(Step7Validator.validate(methods: all).isValid)
    }

    // MARK: - PaymentMethod enum

    func testPaymentMethod_rawValues_areCorrect() {
        XCTAssertEqual(PaymentMethod.cash.rawValue,        "cash")
        XCTAssertEqual(PaymentMethod.card.rawValue,        "card")
        XCTAssertEqual(PaymentMethod.giftCard.rawValue,    "gift_card")
        XCTAssertEqual(PaymentMethod.storeCredit.rawValue, "store_credit")
        XCTAssertEqual(PaymentMethod.check.rawValue,       "check")
    }

    func testPaymentMethod_displayNames_areNonEmpty() {
        for method in PaymentMethod.allCases {
            XCTAssertFalse(method.displayName.isEmpty, "\(method) should have a display name")
        }
    }

    func testPaymentMethod_systemImages_areNonEmpty() {
        for method in PaymentMethod.allCases {
            XCTAssertFalse(method.systemImage.isEmpty, "\(method) should have a system image name")
        }
    }
}
