import XCTest
@testable import DataImport

final class CSVRowParserTests: XCTestCase {

    // MARK: - Basic parsing

    func testEmptyStringReturnsEmpty() {
        let result = CSVRowParser.parse("")
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleValueRow() {
        let result = CSVRowParser.parse("hello")
        XCTAssertEqual(result, [["hello"]])
    }

    func testSimpleRow() {
        let result = CSVRowParser.parse("Alice,Smith,alice@example.com")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], ["Alice", "Smith", "alice@example.com"])
    }

    func testMultipleRows() {
        let csv = "first,last\nAlice,Smith\nBob,Jones"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], ["first", "last"])
        XCTAssertEqual(result[1], ["Alice", "Smith"])
        XCTAssertEqual(result[2], ["Bob", "Jones"])
    }

    func testCRLFNewlines() {
        let csv = "a,b\r\nc,d"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], ["a", "b"])
        XCTAssertEqual(result[1], ["c", "d"])
    }

    // MARK: - Quoted fields

    func testQuotedField() {
        let csv = "\"Alice Smith\",alice@example.com"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result, [["Alice Smith", "alice@example.com"]])
    }

    func testQuotedFieldWithComma() {
        let csv = "\"Smith, Alice\",alice@example.com"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result, [["Smith, Alice", "alice@example.com"]])
    }

    func testEscapedQuoteInsideQuotedField() {
        let csv = "\"He said \"\"hello\"\"\",end"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0][0], "He said \"hello\"")
        XCTAssertEqual(result[0][1], "end")
    }

    func testQuotedFieldWithNewline() {
        let csv = "\"line1\nline2\",next"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0][0], "line1\nline2")
        XCTAssertEqual(result[0][1], "next")
    }

    // MARK: - Edge cases

    func testEmptyFields() {
        let csv = "a,,c"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result, [["a", "", "c"]])
    }

    func testTrailingNewlineIgnored() {
        let csv = "a,b\nc,d\n"
        let result = CSVRowParser.parse(csv)
        // Trailing empty line is filtered
        XCTAssertTrue(result.count >= 2)
        XCTAssertEqual(result[0], ["a", "b"])
        XCTAssertEqual(result[1], ["c", "d"])
    }

    func testSingleColumnMultipleRows() {
        let csv = "name\nAlice\nBob\nCharlie"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result.count, 4)
    }

    // MARK: - parseWithHeaders convenience

    func testParseWithHeaders() {
        let csv = "first_name,last_name,email\nAlice,Smith,a@x.com\nBob,Jones,b@x.com"
        let (headers, rows) = CSVRowParser.parseWithHeaders(csv)
        XCTAssertEqual(headers, ["first_name", "last_name", "email"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["Alice", "Smith", "a@x.com"])
        XCTAssertEqual(rows[1], ["Bob", "Jones", "b@x.com"])
    }

    func testParseWithHeadersEmpty() {
        let (headers, rows) = CSVRowParser.parseWithHeaders("")
        XCTAssertTrue(headers.isEmpty)
        XCTAssertTrue(rows.isEmpty)
    }

    func testParseWithHeadersOnlyHeader() {
        let (headers, rows) = CSVRowParser.parseWithHeaders("col1,col2")
        XCTAssertEqual(headers, ["col1", "col2"])
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Unicode

    func testUnicodeContent() {
        let csv = "名前,メール\n田中,tanaka@example.com"
        let result = CSVRowParser.parse(csv)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0][0], "名前")
        XCTAssertEqual(result[1][0], "田中")
    }
}
