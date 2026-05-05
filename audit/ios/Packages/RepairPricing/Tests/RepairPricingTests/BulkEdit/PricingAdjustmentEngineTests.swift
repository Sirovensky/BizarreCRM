import XCTest
@testable import RepairPricing

// MARK: - §43 Bulk Edit — PricingAdjustmentEngine Unit Tests

final class PricingAdjustmentEngineTests: XCTestCase {

    // MARK: - Rule Validation

    func test_validate_zeroPct_returnsZeroError() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 0)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .zeroValueNotAllowed)
    }

    func test_validate_zeroFixed_returnsZeroError() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: 0)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .zeroValueNotAllowed)
    }

    func test_validate_nanPct_returnsNaNError() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: Double.nan)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .valueIsNaN)
    }

    func test_validate_infFixed_returnsInfiniteError() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: Double.infinity)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .valueIsInfinite)
    }

    func test_validate_pctAbove50_returnsOutOfRange() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 51)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .percentageOutOfRange)
    }

    func test_validate_pctBelowNeg50_returnsOutOfRange() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: -51)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .percentageOutOfRange)
    }

    func test_validate_pctAt50_returnsNil() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 50)
        XCTAssertNil(PricingAdjustmentEngine.validate(rule: rule))
    }

    func test_validate_pctAtNeg50_returnsNil() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: -50)
        XCTAssertNil(PricingAdjustmentEngine.validate(rule: rule))
    }

    func test_validate_fixedAboveMax_returnsOutOfRange() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: 100_001)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .fixedOutOfRange)
    }

    func test_validate_fixedBelowNegMax_returnsOutOfRange() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: -100_001)
        XCTAssertEqual(PricingAdjustmentEngine.validate(rule: rule), .fixedOutOfRange)
    }

    func test_validate_validFixed_returnsNil() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: 5.0)
        XCTAssertNil(PricingAdjustmentEngine.validate(rule: rule))
    }

    func test_validate_validPercentage_returnsNil() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 10)
        XCTAssertNil(PricingAdjustmentEngine.validate(rule: rule))
    }

    // MARK: - Single-price Apply: Percentage

    func test_apply_plusTenPercent_correctResult() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 10)
        let result = PricingAdjustmentEngine.apply(basePrice: 100.0, rule: rule)
        XCTAssertEqual(result, 110.0, accuracy: 0.001)
    }

    func test_apply_minusTenPercent_correctResult() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: -10)
        let result = PricingAdjustmentEngine.apply(basePrice: 50.0, rule: rule)
        XCTAssertEqual(result, 45.0, accuracy: 0.001)
    }

    func test_apply_plusFiftyPercent_correctResult() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 50)
        let result = PricingAdjustmentEngine.apply(basePrice: 200.0, rule: rule)
        XCTAssertEqual(result, 300.0, accuracy: 0.001)
    }

    func test_apply_percentageRoundsToCents() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 10, roundToCents: true)
        // 33.33 * 1.10 = 36.663 → rounds to 36.66
        let result = PricingAdjustmentEngine.apply(basePrice: 33.33, rule: rule)
        XCTAssertEqual(result, 36.66, accuracy: 0.001)
    }

    func test_apply_percentageNoRoundingWhenDisabled() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 10, roundToCents: false)
        let result = PricingAdjustmentEngine.apply(basePrice: 33.33, rule: rule)
        // 33.33 * 1.10 = 36.663
        XCTAssertEqual(result, 36.663, accuracy: 0.0001)
    }

    // MARK: - Single-price Apply: Fixed

    func test_apply_fixedPositive_correctResult() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: 5.0)
        let result = PricingAdjustmentEngine.apply(basePrice: 29.99, rule: rule)
        XCTAssertEqual(result, 34.99, accuracy: 0.001)
    }

    func test_apply_fixedNegative_correctResult() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: -10.0)
        let result = PricingAdjustmentEngine.apply(basePrice: 50.0, rule: rule)
        XCTAssertEqual(result, 40.0, accuracy: 0.001)
    }

    func test_apply_fixedDiscountBelowZero_clampedToZero() {
        let rule = PricingAdjustmentRule(kind: .fixed, value: -200.0)
        let result = PricingAdjustmentEngine.apply(basePrice: 50.0, rule: rule)
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    func test_apply_percentageResultClamped_toMaxRepairPrice() {
        // Percentage increase of a very high price should be clamped
        let rule = PricingAdjustmentRule(kind: .percentage, value: 50)
        let result = PricingAdjustmentEngine.apply(basePrice: 90_000.0, rule: rule)
        // 90_000 * 1.5 = 135_000 → clamped to 100_000
        XCTAssertEqual(result, 100_000.0, accuracy: 0.001)
    }

    // MARK: - Batch Preview

    func test_preview_emptyItems_returnsEmpty() {
        let rule = PricingAdjustmentRule(kind: .percentage, value: 10)
        let results = PricingAdjustmentEngine.preview(items: [], rule: rule)
        XCTAssertTrue(results.isEmpty)
    }

    func test_preview_multipleItems_allAdjusted() {
        let items = [
            PriceInputItem(id: 1, name: "Screen", laborPrice: 100.0),
            PriceInputItem(id: 2, name: "Battery", laborPrice: 50.0),
            PriceInputItem(id: 3, name: "Camera", laborPrice: 80.0)
        ]
        let rule = PricingAdjustmentRule(kind: .percentage, value: 10)
        let results = PricingAdjustmentEngine.preview(items: items, rule: rule)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].newPrice, 110.0, accuracy: 0.001)
        XCTAssertEqual(results[1].newPrice, 55.0, accuracy: 0.001)
        XCTAssertEqual(results[2].newPrice, 88.0, accuracy: 0.001)
    }

    func test_preview_preservesItemOrder() {
        let items = (1...5).map { i in
            PriceInputItem(id: Int64(i), name: "Service \(i)", laborPrice: Double(i) * 10)
        }
        let rule = PricingAdjustmentRule(kind: .fixed, value: 1.0)
        let results = PricingAdjustmentEngine.preview(items: items, rule: rule)
        XCTAssertEqual(results.map { $0.id }, [1, 2, 3, 4, 5])
    }

    func test_preview_deltaCalculatedCorrectly() {
        let items = [PriceInputItem(id: 1, name: "Test", laborPrice: 100.0)]
        let rule = PricingAdjustmentRule(kind: .fixed, value: 25.0)
        let results = PricingAdjustmentEngine.preview(items: items, rule: rule)
        XCTAssertEqual(results[0].delta, 25.0, accuracy: 0.001)
    }

    func test_preview_negativeDeltaIsNegative() {
        let items = [PriceInputItem(id: 1, name: "Test", laborPrice: 100.0)]
        let rule = PricingAdjustmentRule(kind: .percentage, value: -20)
        let results = PricingAdjustmentEngine.preview(items: items, rule: rule)
        XCTAssertLessThan(results[0].delta, 0)
        XCTAssertEqual(results[0].newPrice, 80.0, accuracy: 0.001)
    }

    // MARK: - CSV Parsing: Empty / Header

    func test_parseCSV_emptyString_returnsEmpty() {
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV("")
        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_parseCSV_headerOnly_returnsEmpty() {
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV("name,slug,category,labor_price")
        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_parseCSV_missingRequiredColumns_returnsHeaderError() {
        let csv = "foo,bar\nA,B"
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertFalse(errors.isEmpty)
    }

    // MARK: - CSV Parsing: Valid Rows

    func test_parseCSV_singleValidRow_parsedCorrectly() {
        let csv = """
        name,slug,category,labor_price
        Screen Replacement,screen-replacement,Display,49.99
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(rows[0].name, "Screen Replacement")
        XCTAssertEqual(rows[0].slug, "screen-replacement")
        XCTAssertEqual(rows[0].category, "Display")
        XCTAssertEqual(rows[0].laborPrice, 49.99, accuracy: 0.001)
    }

    func test_parseCSV_multipleValidRows_allParsed() {
        let csv = """
        name,slug,category,labor_price
        Screen,screen,Display,49.99
        Battery,battery,Power,29.99
        Camera,camera,Optics,39.99
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_parseCSV_slugColumnMissing_derivedFromName() {
        // Only name + labor_price columns
        let csv = """
        name,labor_price
        Battery Swap,29.99
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertNil(rows[0].slug)
    }

    func test_parseCSV_categoryMissing_nilCategory() {
        let csv = """
        name,slug,labor_price
        Test,test-slug,10.00
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertNil(rows[0].category)
    }

    // MARK: - CSV Parsing: Invalid Rows

    func test_parseCSV_missingName_rowSkippedWithError() {
        let csv = """
        name,slug,labor_price
        ,screen,49.99
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("name"))
    }

    func test_parseCSV_invalidPrice_rowSkippedWithError() {
        let csv = """
        name,slug,labor_price
        Screen,screen,notanumber
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("labor_price"))
    }

    func test_parseCSV_negativePrice_rowSkipped() {
        let csv = """
        name,labor_price
        Bad Price,-5.00
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(errors.count, 1)
    }

    func test_parseCSV_mixedValidAndInvalid_partialResult() {
        let csv = """
        name,labor_price
        Valid Row,49.99
        ,29.99
        Another Valid,19.99
        BadPrice,xyz
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(errors.count, 2)
    }

    func test_parseCSV_zeroPriceIsValid() {
        let csv = """
        name,labor_price
        Free Diagnostic,0
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(rows[0].laborPrice, 0.0, accuracy: 0.001)
    }

    func test_parseCSV_extraColumnsIgnored() {
        let csv = """
        name,slug,extra_column,labor_price,another_extra
        Screen,screen-fix,ignored,49.99,also-ignored
        """
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(rows[0].name, "Screen")
        XCTAssertEqual(rows[0].laborPrice, 49.99, accuracy: 0.001)
    }

    func test_parseCSV_rowNumbers_oneBasedIncludingHeader() {
        let csv = """
        name,labor_price
        Valid,10.00
        ,20.00
        Valid2,30.00
        Bad,notanumber
        """
        let (_, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(csv)
        XCTAssertEqual(errors.count, 2)
        // Header = row 1, first data row = row 2
        XCTAssertEqual(errors[0].row, 3) // second data row (missing name)
        XCTAssertEqual(errors[1].row, 5) // fourth data row (bad price)
    }

    // MARK: - CSVParseError

    func test_csvParseError_errorDescription_includesRowNumber() {
        let err = CSVParseError(row: 42, message: "Some problem.")
        XCTAssertTrue(err.errorDescription?.contains("42") == true)
    }
}
