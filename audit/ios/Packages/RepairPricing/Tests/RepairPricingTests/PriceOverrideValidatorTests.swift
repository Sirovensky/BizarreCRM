import XCTest
@testable import RepairPricing

/// §43.3 — PriceOverrideValidator unit tests.
final class PriceOverrideValidatorTests: XCTestCase {

    // MARK: - Price validation (tenant scope)

    func test_emptyPrice_returnsEmptyError() {
        let result = PriceOverrideValidator.validate(rawPrice: "", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .failure(.priceEmpty))
    }

    func test_whitespacePrice_returnsEmptyError() {
        let result = PriceOverrideValidator.validate(rawPrice: "   ", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .failure(.priceEmpty))
    }

    func test_nonNumericPrice_returnsInvalid() {
        let result = PriceOverrideValidator.validate(rawPrice: "abc", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .failure(.priceInvalid))
    }

    func test_zeroPrice_returnsNotPositive() {
        let result = PriceOverrideValidator.validate(rawPrice: "0", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .failure(.priceNotPositive))
    }

    func test_negativePrice_returnsNotPositive() {
        let result = PriceOverrideValidator.validate(rawPrice: "-5", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .failure(.priceNotPositive))
    }

    func test_validPrice_returnsCorrectCents() {
        let result = PriceOverrideValidator.validate(rawPrice: "29.99", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .success(2999))
    }

    func test_wholeNumberPrice_returnsCorrectCents() {
        let result = PriceOverrideValidator.validate(rawPrice: "100", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .success(10000))
    }

    func test_smallPrice_returnsCorrectCents() {
        let result = PriceOverrideValidator.validate(rawPrice: "0.01", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .success(1))
    }

    // MARK: - Customer scope validation

    func test_customerScope_noCustomerId_returnsError() {
        let result = PriceOverrideValidator.validate(rawPrice: "10.00", scope: .customer, customerId: nil)
        XCTAssertEqual(result, .failure(.customerIdRequiredForCustomerScope))
    }

    func test_customerScope_emptyCustomerId_returnsError() {
        let result = PriceOverrideValidator.validate(rawPrice: "10.00", scope: .customer, customerId: "   ")
        XCTAssertEqual(result, .failure(.customerIdRequiredForCustomerScope))
    }

    func test_customerScope_validCustomerId_returnsSuccess() {
        let result = PriceOverrideValidator.validate(rawPrice: "15.00", scope: .customer, customerId: "cust-123")
        XCTAssertEqual(result, .success(1500))
    }

    func test_tenantScope_customerIdIgnored() {
        // For tenant scope, customerId is irrelevant — should still succeed
        let result = PriceOverrideValidator.validate(rawPrice: "20.00", scope: .tenant, customerId: nil)
        XCTAssertEqual(result, .success(2000))
    }

    // MARK: - Rounding

    func test_priceRounding_roundsHalfUp() {
        // 19.999 → $20.00 → 2000 cents
        let result = PriceOverrideValidator.validate(rawPrice: "19.999", scope: .tenant, customerId: nil)
        if case .success(let cents) = result {
            XCTAssertEqual(cents, 2000)
        } else {
            XCTFail("Expected success, got \(result)")
        }
    }

    // MARK: - Error descriptions

    func test_errorDescriptions_areNotEmpty() {
        for error in [
            PriceOverrideValidator.ValidationError.priceEmpty,
            .priceInvalid,
            .priceNotPositive,
            .customerIdRequiredForCustomerScope
        ] {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "Error description should not be empty for \(error)")
        }
    }
}
