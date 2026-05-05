import XCTest
@testable import DataImport

// MARK: - ImportLivePreviewPaneTests

/// Unit tests for the mapping-status badge computation and cell coloring logic
/// mirrored from `ImportLivePreviewPane`. The view itself is a pure SwiftUI
/// rendering surface; we test the data transformations here.
final class ImportLivePreviewPaneTests: XCTestCase {

    // MARK: - Mapping status badge

    func test_mappedCount_allMapped() {
        let columns = ["first_name", "last_name", "email"]
        let mapping: [String: String] = [
            "first_name": CRMField.firstName.rawValue,
            "last_name":  CRMField.lastName.rawValue,
            "email":      CRMField.email.rawValue,
        ]
        let status = MappingStatus(columns: columns, mapping: mapping)
        XCTAssertEqual(status.mapped, 3)
        XCTAssertEqual(status.total, 3)
        XCTAssertTrue(status.allMapped)
    }

    func test_mappedCount_partiallyMapped() {
        let columns = ["first_name", "last_name", "email", "unknown_col"]
        let mapping: [String: String] = [
            "first_name": CRMField.firstName.rawValue,
            "last_name":  CRMField.lastName.rawValue,
        ]
        let status = MappingStatus(columns: columns, mapping: mapping)
        XCTAssertEqual(status.mapped, 2)
        XCTAssertEqual(status.total, 4)
        XCTAssertFalse(status.allMapped)
    }

    func test_mappedCount_emptyMapping() {
        let columns = ["col_a", "col_b"]
        let status = MappingStatus(columns: columns, mapping: [:])
        XCTAssertEqual(status.mapped, 0)
        XCTAssertFalse(status.allMapped)
    }

    func test_mappedCount_emptyValueNotCounted() {
        // A key with an empty string value should NOT count as mapped.
        let columns = ["col_a"]
        let mapping: [String: String] = ["col_a": ""]
        let status = MappingStatus(columns: columns, mapping: mapping)
        XCTAssertEqual(status.mapped, 0)
        XCTAssertFalse(status.allMapped)
    }

    // MARK: - Preview row slicing (first 10)

    func test_previewSlices_first10Rows() {
        let rows = (1...25).map { i in ["value\(i)"] }
        let preview = ImportPreview(columns: ["col"], rows: rows, totalRows: 25)
        let sliced = Array(preview.rows.prefix(10))
        XCTAssertEqual(sliced.count, 10)
        XCTAssertEqual(sliced.first, ["value1"])
        XCTAssertEqual(sliced.last, ["value10"])
    }

    func test_previewSlices_fewerThan10Rows() {
        let rows = (1...5).map { i in ["value\(i)"] }
        let preview = ImportPreview(columns: ["col"], rows: rows, totalRows: 5)
        let sliced = Array(preview.rows.prefix(10))
        XCTAssertEqual(sliced.count, 5)
    }

    func test_previewSlices_emptyRows() {
        let preview = ImportPreview(columns: ["col"], rows: [], totalRows: 0)
        XCTAssertTrue(Array(preview.rows.prefix(10)).isEmpty)
    }

    // MARK: - Flagged row detection

    func test_flaggedRow_matchesRowAndColumn() {
        let flaggedRows = [ImportRowError(row: 2, column: "email", reason: "Invalid")]
        // Row 2 (1-based index) with column "email" should be flagged
        let hasError = flaggedRows.contains { $0.row == 2 && ($0.column == "email" || $0.column == nil) }
        XCTAssertTrue(hasError)
    }

    func test_flaggedRow_noMatchDifferentRow() {
        let flaggedRows = [ImportRowError(row: 5, column: "email", reason: "Invalid")]
        let hasError = flaggedRows.contains { $0.row == 2 && ($0.column == "email" || $0.column == nil) }
        XCTAssertFalse(hasError)
    }

    func test_flaggedRow_nilColumnMatchesAnyColumn() {
        let flaggedRows = [ImportRowError(row: 3, column: nil, reason: "Missing required field")]
        // A nil-column error on row 3 should flag any cell on that row
        let hasError = flaggedRows.contains { $0.row == 3 && ($0.column == "first_name" || $0.column == nil) }
        XCTAssertTrue(hasError)
    }

    // MARK: - CRMField display name resolution

    func test_crmFieldDisplayName_resolvedForValidRawValue() {
        let rawValue = CRMField.email.rawValue
        let displayName = CRMField(rawValue: rawValue)?.displayName
        XCTAssertEqual(displayName, "Email")
    }

    func test_crmFieldDisplayName_nilForInvalidRawValue() {
        let displayName = CRMField(rawValue: "nonexistent.field")?.displayName
        XCTAssertNil(displayName)
    }

    func test_crmFieldDisplayName_allFieldsHaveDisplayNames() {
        for field in CRMField.allCases {
            XCTAssertFalse(field.displayName.isEmpty, "CRMField.\(field) has no display name")
        }
    }
}

// MARK: - Test helpers

/// Mirrors the mapping-status computation from `ImportLivePreviewPane`.
private struct MappingStatus {
    let mapped: Int
    let total: Int
    var allMapped: Bool { mapped == total }

    init(columns: [String], mapping: [String: String]) {
        total  = columns.count
        mapped = mapping.values.filter { !$0.isEmpty }.count
    }
}
