import XCTest
@testable import DataImport

final class ImportColumnMapperTests: XCTestCase {

    // MARK: - Exact match

    func testExactMatchFirstName() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["first_name"])
        XCTAssertEqual(mapping["first_name"], CRMField.firstName.rawValue)
    }

    func testExactMatchLastName() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["last_name"])
        XCTAssertEqual(mapping["last_name"], CRMField.lastName.rawValue)
    }

    func testExactMatchPhone() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["phone"])
        XCTAssertEqual(mapping["phone"], CRMField.phone.rawValue)
    }

    func testExactMatchEmail() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["email"])
        XCTAssertEqual(mapping["email"], CRMField.email.rawValue)
    }

    func testExactMatchDisplayName() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["First Name"])
        XCTAssertEqual(mapping["First Name"], CRMField.firstName.rawValue)
    }

    // MARK: - Fuzzy match (Levenshtein < 3)

    func testFuzzyMatchFirstNameTypo() {
        // "firstname" vs "first name" — after normalization both become "firstname"
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["firstname"])
        XCTAssertEqual(mapping["firstname"], CRMField.firstName.rawValue)
    }

    func testFuzzyMatchEmailTypo() {
        // "emal" → distance 1 from "email"
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["emal"])
        XCTAssertEqual(mapping["emal"], CRMField.email.rawValue)
    }

    func testFuzzyMatchPhoneVariant() {
        // "Phone Number" → after normalization "phonenumber" distance from "phone" = 6 → no match
        // But "cell" probably won't match either — just verify no crash
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["cell"])
        // "cell" doesn't match phone with distance < 3 — this is correct
        XCTAssertNil(mapping["cell"])
    }

    func testUnmappableColumnNotIncluded() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["purchase_order_id"])
        // No CRM field should match this obscure column
        XCTAssertNil(mapping["purchase_order_id"])
    }

    // MARK: - Multiple columns

    func testAutoMapMultipleColumns() {
        let columns = ["first_name", "last_name", "email", "phone", "irrelevant_xyz"]
        let mapping = ImportColumnMapper.autoMap(sourceColumns: columns)
        XCTAssertEqual(mapping["first_name"], CRMField.firstName.rawValue)
        XCTAssertEqual(mapping["last_name"], CRMField.lastName.rawValue)
        XCTAssertEqual(mapping["email"], CRMField.email.rawValue)
        XCTAssertEqual(mapping["phone"], CRMField.phone.rawValue)
        // irrelevant_xyz should not appear in mapping (or have nil value)
        XCTAssertNil(mapping["irrelevant_xyz"])
    }

    func testEmptyColumnsProducesEmptyMapping() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: [])
        XCTAssertTrue(mapping.isEmpty)
    }

    // MARK: - allRequiredMapped

    func testAllRequiredMappedTrue() {
        let mapping: [String: String] = [
            "fn": CRMField.firstName.rawValue,
            "ln": CRMField.lastName.rawValue,
            "ph": CRMField.phone.rawValue,
            "em": CRMField.email.rawValue
        ]
        XCTAssertTrue(ImportColumnMapper.allRequiredMapped(mapping))
    }

    func testAllRequiredMappedFalse_missingPhone() {
        let mapping: [String: String] = [
            "fn": CRMField.firstName.rawValue,
            "ln": CRMField.lastName.rawValue,
            "em": CRMField.email.rawValue
        ]
        XCTAssertFalse(ImportColumnMapper.allRequiredMapped(mapping))
    }

    func testAllRequiredMappedFalse_emptyMapping() {
        XCTAssertFalse(ImportColumnMapper.allRequiredMapped([:]))
    }

    func testAllRequiredMappedWithOptionalExtra() {
        let mapping: [String: String] = [
            "fn": CRMField.firstName.rawValue,
            "ln": CRMField.lastName.rawValue,
            "ph": CRMField.phone.rawValue,
            "em": CRMField.email.rawValue,
            "addr": CRMField.address.rawValue
        ]
        XCTAssertTrue(ImportColumnMapper.allRequiredMapped(mapping))
    }

    // MARK: - missingRequired

    func testMissingRequired_allMissing() {
        let missing = ImportColumnMapper.missingRequired([:])
        XCTAssertEqual(missing.count, CRMField.requiredFields.count)
    }

    func testMissingRequired_noneWhenAllMapped() {
        let mapping: [String: String] = [
            "a": CRMField.firstName.rawValue,
            "b": CRMField.lastName.rawValue,
            "c": CRMField.phone.rawValue,
            "d": CRMField.email.rawValue
        ]
        XCTAssertTrue(ImportColumnMapper.missingRequired(mapping).isEmpty)
    }

    func testMissingRequired_returnsCorrectField() {
        let mapping: [String: String] = [
            "a": CRMField.firstName.rawValue,
            "b": CRMField.lastName.rawValue,
            "c": CRMField.phone.rawValue
            // email missing
        ]
        let missing = ImportColumnMapper.missingRequired(mapping)
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first, .email)
    }

    // MARK: - Levenshtein distances

    func testLevenshteinIdentical() {
        XCTAssertEqual(ImportColumnMapper.levenshtein("abc", "abc"), 0)
    }

    func testLevenshteinEmpty() {
        XCTAssertEqual(ImportColumnMapper.levenshtein("", "abc"), 3)
        XCTAssertEqual(ImportColumnMapper.levenshtein("abc", ""), 3)
        XCTAssertEqual(ImportColumnMapper.levenshtein("", ""), 0)
    }

    func testLevenshteinOneSubstitution() {
        XCTAssertEqual(ImportColumnMapper.levenshtein("emal", "email"), 1)
    }

    func testLevenshteinOneDeletion() {
        XCTAssertEqual(ImportColumnMapper.levenshtein("phne", "phone"), 1)
    }

    func testLevenshteinTotallyDifferent() {
        XCTAssertGreaterThanOrEqual(ImportColumnMapper.levenshtein("xyz", "email"), 3)
    }

    // MARK: - normalize

    func testNormalizeStripsCustomerPrefix() {
        XCTAssertEqual(ImportColumnMapper.normalize("customer.first_name"), "firstname")
    }

    func testNormalizeLowercase() {
        XCTAssertEqual(ImportColumnMapper.normalize("PHONE"), "phone")
    }

    func testNormalizeStripsUnderscores() {
        XCTAssertEqual(ImportColumnMapper.normalize("last_name"), "lastname")
    }

    func testNormalizeStripsSpaces() {
        XCTAssertEqual(ImportColumnMapper.normalize("First Name"), "firstname")
    }
}
