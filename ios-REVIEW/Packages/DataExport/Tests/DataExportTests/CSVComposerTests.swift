import Testing
@testable import DataExport

// MARK: - CSVComposerTests

@Suite("CSVComposer — RFC-4180 compliance")
struct CSVComposerTests {

    // MARK: - Header row

    @Test("Header row is the first record")
    func headerIsFirstRecord() {
        let csv = CSVComposer.compose(rows: [["Alice", "alice@example.com"]], columns: ["Name", "Email"])
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == "Name,Email")
        #expect(lines[1] == "Alice,alice@example.com")
    }

    @Test("Empty rows produces header only")
    func emptyRowsProducesHeaderOnly() {
        let csv = CSVComposer.compose(rows: [], columns: ["A", "B", "C"])
        #expect(csv == "A,B,C")
    }

    @Test("Multiple data rows separated by CRLF")
    func multipleRowsCRLF() {
        let csv = CSVComposer.compose(
            rows: [["1", "Alice"], ["2", "Bob"]],
            columns: ["ID", "Name"]
        )
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "ID,Name")
        #expect(lines[1] == "1,Alice")
        #expect(lines[2] == "2,Bob")
    }

    // MARK: - Quoting rules (RFC-4180 §2.7)

    @Test("Field containing comma is quoted")
    func fieldWithCommaIsQuoted() {
        let csv = CSVComposer.compose(rows: [["Smith, John"]], columns: ["Name"])
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[1] == "\"Smith, John\"")
    }

    @Test("Field containing double-quote has quotes doubled")
    func fieldWithDoubleQuoteIsDoubled() {
        let csv = CSVComposer.compose(rows: [["He said \"Hello\""]], columns: ["Quote"])
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[1] == "\"He said \"\"Hello\"\"\"")
    }

    @Test("Field containing newline is quoted")
    func fieldWithNewlineIsQuoted() {
        let csv = CSVComposer.compose(rows: [["Line1\nLine2"]], columns: ["Notes"])
        let lines = csv.components(separatedBy: "\r\n")
        // The field itself contains \n so whole field is wrapped in quotes
        #expect(lines[1].hasPrefix("\""))
        #expect(lines[1].hasSuffix("\""))
    }

    @Test("Field containing CR is quoted")
    func fieldWithCRIsQuoted() {
        let csv = CSVComposer.compose(rows: [["A\rB"]], columns: ["Col"])
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[1].hasPrefix("\""))
    }

    @Test("Plain field is not quoted")
    func plainFieldNotQuoted() {
        let result = CSVComposer.escapeField("hello world")
        #expect(result == "hello world")
    }

    @Test("Empty field is not quoted")
    func emptyFieldNotQuoted() {
        let result = CSVComposer.escapeField("")
        #expect(result == "")
    }

    // MARK: - Multi-column rows

    @Test("Multiple columns joined by comma")
    func multipleColumnsJoined() {
        let csv = CSVComposer.compose(
            rows: [["Alice", "30", "alice@example.com"]],
            columns: ["Name", "Age", "Email"]
        )
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == "Name,Age,Email")
        #expect(lines[1] == "Alice,30,alice@example.com")
    }

    @Test("Field with only spaces is not quoted")
    func fieldWithSpacesNotQuoted() {
        let result = CSVComposer.escapeField("   ")
        #expect(result == "   ")
    }

    @Test("Field with comma AND double-quote is both quoted and doubled")
    func fieldWithCommaAndQuote() {
        let result = CSVComposer.escapeField("a,\"b\"")
        #expect(result == "\"a,\"\"b\"\"\"")
    }

    // MARK: - Edge cases

    @Test("Empty columns list produces empty header record")
    func emptyColumnsEmptyHeader() {
        let csv = CSVComposer.compose(rows: [["x"]], columns: [])
        // columns [] → header is empty string, row is "x"
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == "")
        #expect(lines[1] == "x")
    }

    @Test("Unicode content preserved")
    func unicodePreserved() {
        let csv = CSVComposer.compose(rows: [["héllo", "wörld"]], columns: ["A", "B"])
        #expect(csv.contains("héllo"))
        #expect(csv.contains("wörld"))
    }
}
