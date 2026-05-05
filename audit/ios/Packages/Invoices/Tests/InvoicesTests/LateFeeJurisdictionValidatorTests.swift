import XCTest
@testable import Invoices

final class LateFeeJurisdictionValidatorTests: XCTestCase {

    func test_registry_lookupCaseInsensitive() {
        XCTAssertNotNil(LateFeeJurisdictionRegistry.limit(for: "us-ca"))
        XCTAssertNotNil(LateFeeJurisdictionRegistry.limit(for: "US-CA"))
        XCTAssertNil(LateFeeJurisdictionRegistry.limit(for: "ZZ-XX"))
    }

    func test_aprAboveCap_warns() {
        // CA cap = 10% APR. 0.05 % per day × 365 ≈ 18.25 % → exceeds cap.
        let policy = LateFeePolicy(percentPerDay: 0.05, gracePeriodDays: 0)
        let limit = LateFeeJurisdictionRegistry.limit(for: "US-CA")!
        let warns = LateFeeJurisdictionValidator.validate(
            policy: policy, invoiceTotalCents: 100_000, limit: limit
        )
        XCTAssertTrue(warns.contains { $0.kind == .aprExceedsCap })
    }

    func test_aprBelowCap_noWarning() {
        // 0.02% per day × 365 ≈ 7.3% — under CA's 10% APR cap.
        let policy = LateFeePolicy(percentPerDay: 0.02, gracePeriodDays: 0)
        let limit = LateFeeJurisdictionRegistry.limit(for: "US-CA")!
        let warns = LateFeeJurisdictionValidator.validate(
            policy: policy, invoiceTotalCents: 100_000, limit: limit
        )
        XCTAssertFalse(warns.contains { $0.kind == .aprExceedsCap })
    }

    func test_flatFeeAboveInvoicePctCap_warns() {
        // CA cap on flat = 10% of invoice. $20 fee on $100 invoice = 20%.
        let policy = LateFeePolicy(flatFeeCents: 2_000, gracePeriodDays: 0)
        let limit = LateFeeJurisdictionRegistry.limit(for: "US-CA")!
        let warns = LateFeeJurisdictionValidator.validate(
            policy: policy, invoiceTotalCents: 10_000, limit: limit
        )
        XCTAssertTrue(warns.contains { $0.kind == .flatFeeExceedsCap })
    }

    func test_flatFeeUnderCap_noWarning() {
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 0)
        let limit = LateFeeJurisdictionRegistry.limit(for: "US-CA")!
        let warns = LateFeeJurisdictionValidator.validate(
            policy: policy, invoiceTotalCents: 100_000, limit: limit
        )
        XCTAssertTrue(warns.isEmpty)
    }
}
