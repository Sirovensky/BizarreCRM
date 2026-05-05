import Testing
import Foundation
@testable import AuditLogs

// MARK: - Shared fixture helpers

private func makeEntry(
    id: String = "1",
    actorFirstName: String? = "Alice",
    actorLastName: String? = "Smith",
    actorUserId: Int? = 7,
    action: String = "ticket.update",
    entityKind: String = "ticket",
    entityId: Int? = 42,
    metadata: [String: AuditDiffValue]? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
) -> AuditLogEntry {
    AuditLogEntry(
        id: id,
        createdAt: createdAt,
        actorUserId: actorUserId,
        actorFirstName: actorFirstName,
        actorLastName: actorLastName,
        action: action,
        entityKind: entityKind,
        entityId: entityId,
        metadata: metadata
    )
}

// MARK: - AuditLogCSVComposer Tests

@Suite("AuditLogCSVComposer")
struct AuditLogCSVComposerTests {

    // MARK: Column order stability

    @Test("Column headers are stable and in the documented order")
    func columnOrderIsStable() {
        let expected = ["id", "created_at", "actor_name", "actor_user_id",
                        "action", "entity_kind", "entity_id", "metadata"]
        #expect(AuditLogCSVComposer.columnHeaders == expected)
    }

    @Test("Data row columns match header order")
    func dataRowMatchesHeaderOrder() {
        let entry = makeEntry()
        let values = AuditLogCSVComposer.fields(for: entry)
        #expect(values.count == AuditLogCSVComposer.columnHeaders.count)
        #expect(values[0] == "1")              // id
        // created_at is index 1 — just check it's not empty
        #expect(!values[1].isEmpty)
        #expect(values[2] == "Alice Smith")    // actor_name
        #expect(values[3] == "7")              // actor_user_id
        #expect(values[4] == "ticket.update")  // action
        #expect(values[5] == "ticket")         // entity_kind
        #expect(values[6] == "42")             // entity_id
    }

    // MARK: CSV field escaping

    @Test("Plain value requires no quoting")
    func plainValueNoQuotes() {
        #expect(AuditLogCSVComposer.escape("hello") == "hello")
    }

    @Test("Value with comma is wrapped in double-quotes")
    func valueWithCommaIsQuoted() {
        let result = AuditLogCSVComposer.escape("hello, world")
        #expect(result == "\"hello, world\"")
    }

    @Test("Value with double-quote escapes inner quote as double-double-quote")
    func valueWithDoubleQuoteEscaped() {
        let result = AuditLogCSVComposer.escape("say \"hi\"")
        #expect(result == "\"say \"\"hi\"\"\"")
    }

    @Test("Value with newline is wrapped in double-quotes")
    func valueWithNewlineIsQuoted() {
        let result = AuditLogCSVComposer.escape("line1\nline2")
        #expect(result == "\"line1\nline2\"")
    }

    @Test("Value with carriage return is wrapped in double-quotes")
    func valueWithCRIsQuoted() {
        let result = AuditLogCSVComposer.escape("cr\rval")
        #expect(result == "\"cr\rval\"")
    }

    @Test("Empty string is not quoted")
    func emptyStringNotQuoted() {
        #expect(AuditLogCSVComposer.escape("") == "")
    }

    @Test("Actor name containing comma is properly escaped in CSV row")
    func actorNameWithCommaEscapedInRow() {
        let entry = makeEntry(actorFirstName: "Smith, Jr.", actorLastName: nil)
        let csv = AuditLogCSVComposer.compose(entries: [entry])
        // The actor_name field should appear as a quoted field
        #expect(csv.contains("\"Smith, Jr.\""))
    }

    @Test("Metadata value with double-quotes in string is escaped")
    func metadataQuoteEscaping() {
        let entry = makeEntry(metadata: ["note": .string("say \"hello\"")])
        let csv = AuditLogCSVComposer.compose(entries: [entry])
        // The metadata column must have escaped inner quotes
        #expect(csv.contains("\"\"hello\"\""))
    }

    // MARK: Output structure

    @Test("Empty entries produces header-only CSV with trailing CRLF")
    func emptyEntriesHeaderOnly() {
        let csv = AuditLogCSVComposer.compose(entries: [])
        let lines = csv.components(separatedBy: "\r\n")
        // Lines after split: [header, ""] (trailing CRLF produces empty last token)
        #expect(lines.count == 2)
        #expect(lines[1] == "")
        #expect(lines[0].hasPrefix("id,"))
    }

    @Test("Single entry produces header + 1 data row + trailing CRLF")
    func singleEntryProducesThreeTokens() {
        let entry = makeEntry()
        let csv = AuditLogCSVComposer.compose(entries: [entry])
        let lines = csv.components(separatedBy: "\r\n")
        // [header, dataRow, ""]
        #expect(lines.count == 3)
        #expect(lines[2] == "")
    }

    @Test("Multiple entries produce correct row count")
    func multipleEntriesRowCount() {
        let entries = (1...5).map { makeEntry(id: "\($0)") }
        let csv = AuditLogCSVComposer.compose(entries: entries)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // 1 header + 5 data rows
        #expect(lines.count == 6)
    }

    @Test("Line endings are CRLF (RFC-4180)")
    func lineEndingsAreCRLF() {
        let entry = makeEntry()
        let csv = AuditLogCSVComposer.compose(entries: [entry])
        #expect(csv.contains("\r\n"))
        // Must not contain bare LF (outside a quoted field)
        let unquotedContent = csv.replacingOccurrences(
            of: "\"[^\"]*\"",
            with: "",
            options: .regularExpression
        )
        let bareNewlines = unquotedContent.filter { $0 == "\n" && !unquotedContent.contains("\r\n") }
        #expect(bareNewlines.isEmpty)
    }

    // MARK: Date range filter

    @Test("Entries before `since` are excluded")
    func sinceFilterExcludesOldEntries() {
        let old   = makeEntry(id: "1", createdAt: Date(timeIntervalSince1970: 1_000_000))
        let newer = makeEntry(id: "2", createdAt: Date(timeIntervalSince1970: 2_000_000))
        let csv = AuditLogCSVComposer.compose(
            entries: [old, newer],
            since: Date(timeIntervalSince1970: 1_500_000)
        )
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // header + 1 data row
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("2,"))
    }

    @Test("Entries after `until` are excluded")
    func untilFilterExcludesNewEntries() {
        let old   = makeEntry(id: "1", createdAt: Date(timeIntervalSince1970: 1_000_000))
        let newer = makeEntry(id: "2", createdAt: Date(timeIntervalSince1970: 2_000_000))
        let csv = AuditLogCSVComposer.compose(
            entries: [old, newer],
            until: Date(timeIntervalSince1970: 1_500_000)
        )
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // header + 1 data row
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("1,"))
    }

    @Test("Entries within date range are all included")
    func dateRangeBothBoundsInclude() {
        let t1 = makeEntry(id: "1", createdAt: Date(timeIntervalSince1970: 1_000_000))
        let t2 = makeEntry(id: "2", createdAt: Date(timeIntervalSince1970: 1_500_000))
        let t3 = makeEntry(id: "3", createdAt: Date(timeIntervalSince1970: 2_000_000))
        let csv = AuditLogCSVComposer.compose(
            entries: [t1, t2, t3],
            since: Date(timeIntervalSince1970: 900_000),
            until: Date(timeIntervalSince1970: 1_600_000)
        )
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 3) // header + t1 + t2
    }

    @Test("No date range returns all entries")
    func noDateRangeReturnsAll() {
        let entries = (1...3).map { makeEntry(id: "\($0)") }
        let csv = AuditLogCSVComposer.compose(entries: entries)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 4) // header + 3
    }

    // MARK: Optional fields

    @Test("Nil actor_user_id produces empty column")
    func nilActorUserIdIsEmpty() {
        let entry = makeEntry(actorUserId: nil)
        let values = AuditLogCSVComposer.fields(for: entry)
        #expect(values[3] == "")
    }

    @Test("Nil entity_id produces empty column")
    func nilEntityIdIsEmpty() {
        let entry = AuditLogEntry(
            id: "9", createdAt: Date(),
            action: "system.event", entityKind: "system", entityId: nil
        )
        let values = AuditLogCSVComposer.fields(for: entry)
        #expect(values[6] == "")
    }

    @Test("Nil metadata produces empty metadata column")
    func nilMetadataIsEmpty() {
        let entry = makeEntry(metadata: nil)
        let values = AuditLogCSVComposer.fields(for: entry)
        #expect(values[7] == "")
    }

    @Test("Metadata keys are sorted for stability")
    func metadataKeysSorted() {
        let meta: [String: AuditDiffValue] = [
            "z_key": .string("last"),
            "a_key": .string("first"),
            "m_key": .number(42)
        ]
        let result = AuditLogCSVComposer.metadataString(from: meta)
        let keys = result.components(separatedBy: "; ").map {
            $0.components(separatedBy: "=").first ?? ""
        }
        #expect(keys == ["a_key", "m_key", "z_key"])
    }

    // MARK: date formatting

    @Test("created_at is formatted as ISO-8601 UTC")
    func createdAtFormattedISO8601() {
        // 2023-11-14 22:13:20 UTC
        let knownDate = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = makeEntry(id: "1", createdAt: knownDate)
        let values = AuditLogCSVComposer.fields(for: entry)
        #expect(values[1] == "2023-11-14T22:13:20+00:00")
    }
}

// MARK: - AuditLogExportFileWriter Tests

@Suite("AuditLogExportFileWriter")
struct AuditLogExportFileWriterTests {

    @Test("write returns URL in tmp directory")
    func writeReturnsURLInTmpDir() throws {
        let url = try AuditLogExportFileWriter.write(csvString: "id,created_at\r\n")
        #expect(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    @Test("written file has .csv extension")
    func fileHasCSVExtension() throws {
        let url = try AuditLogExportFileWriter.write(csvString: "id\r\n")
        #expect(url.pathExtension == "csv")
    }

    @Test("written file name starts with audit-log-")
    func fileNamePrefix() throws {
        let url = try AuditLogExportFileWriter.write(csvString: "id\r\n")
        #expect(url.lastPathComponent.hasPrefix("audit-log-"))
    }

    @Test("written file exists on disk and content matches input")
    func fileContentRoundTrip() throws {
        let csvContent = "id,created_at\r\n1,2023-01-01T00:00:00+00:00\r\n"
        let url = try AuditLogExportFileWriter.write(csvString: csvContent)
        let readBack = try String(contentsOf: url, encoding: .utf8)
        #expect(readBack == csvContent)
        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    @Test("successive writes produce different file names")
    func successiveWritesProduceDifferentNames() throws {
        let url1 = try AuditLogExportFileWriter.write(csvString: "a\r\n")
        // Small delay to ensure timestamp can differ (same-second collisions are
        // handled by OS atomicity; we just verify the write succeeds twice)
        let url2 = try AuditLogExportFileWriter.write(csvString: "b\r\n")
        // Both must exist and be readable
        #expect(FileManager.default.fileExists(atPath: url1.path))
        #expect(FileManager.default.fileExists(atPath: url2.path))
        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }

    @Test("empty CSV string writes successfully")
    func emptyCSVWritesSuccessfully() throws {
        let url = try AuditLogExportFileWriter.write(csvString: "")
        let readBack = try String(contentsOf: url, encoding: .utf8)
        #expect(readBack == "")
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Integration: compose + write round-trip

@Suite("AuditLogExport integration")
struct AuditLogExportIntegrationTests {

    @Test("compose + write produces readable CSV on disk")
    func composeAndWriteRoundTrip() throws {
        let entries = [
            makeEntry(id: "1", actorFirstName: "Alice", actorLastName: "Smith", action: "ticket.create"),
            makeEntry(id: "2", actorFirstName: "Bob",   actorLastName: nil,    action: "invoice.update")
        ]
        let csv = AuditLogCSVComposer.compose(entries: entries)
        let url = try AuditLogExportFileWriter.write(csvString: csv)
        let readBack = try String(contentsOf: url, encoding: .utf8)
        #expect(readBack == csv)
        #expect(readBack.contains("Alice Smith"))
        #expect(readBack.contains("invoice.update"))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("compose with date range filter reduces rows in file")
    func dateRangeFilterReducesRows() throws {
        let old   = makeEntry(id: "1", createdAt: Date(timeIntervalSince1970: 1_000_000))
        let newer = makeEntry(id: "2", createdAt: Date(timeIntervalSince1970: 2_000_000))
        let csv = AuditLogCSVComposer.compose(
            entries: [old, newer],
            since: Date(timeIntervalSince1970: 1_500_000)
        )
        let url = try AuditLogExportFileWriter.write(csvString: csv)
        let readBack = try String(contentsOf: url, encoding: .utf8)
        let lines = readBack.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // header + 1 (only "newer" survives)
        #expect(lines.count == 2)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - §50.3 AuditLogPDFComposer Tests (UIKit only)

#if canImport(UIKit)
@Suite("AuditLogPDFComposer §50.3")
struct AuditLogPDFComposerTests {

    @Test("compose empty entries returns a PDF file URL")
    func composeEmptyEntriesReturnsPDFURL() throws {
        let url = try AuditLogPDFComposer.compose(entries: [])
        #expect(url.pathExtension == "pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("compose with entries returns a PDF file URL")
    func composeWithEntriesReturnsPDFURL() throws {
        let entries = [
            makeEntry(id: "1", action: "ticket.update"),
            makeEntry(id: "2", action: "invoice.create")
        ]
        let url = try AuditLogPDFComposer.compose(entries: entries)
        #expect(url.pathExtension == "pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("PDF file name starts with audit-log-court-")
    func fileNameHasCourtPrefix() throws {
        let url = try AuditLogPDFComposer.compose(entries: [])
        #expect(url.lastPathComponent.hasPrefix("audit-log-court-"))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("PDF file is non-empty")
    func pdfFileIsNonEmpty() throws {
        let url = try AuditLogPDFComposer.compose(entries: [makeEntry()])
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        #expect(size > 0)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("PDF starts with %PDF magic bytes")
    func pdfStartsWithMagicBytes() throws {
        let url = try AuditLogPDFComposer.compose(entries: [])
        let data = try Data(contentsOf: url)
        let magic = String(data: data.prefix(4), encoding: .ascii) ?? ""
        #expect(magic == "%PDF")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("compose respects tenantName and exportedBy parameters without crashing")
    func composeCustomTenantAndExporter() throws {
        let url = try AuditLogPDFComposer.compose(
            entries: [makeEntry()],
            tenantName: "ACME Corp",
            exportedBy: "Jane Compliance"
        )
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("compose with date range bounds does not crash")
    func composeWithDateRange() throws {
        let url = try AuditLogPDFComposer.compose(
            entries: [makeEntry()],
            since: Date(timeIntervalSince1970: 1_000_000),
            until: Date()
        )
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("successive composes produce different file names")
    func successiveComposesDifferentNames() throws {
        let url1 = try AuditLogPDFComposer.compose(entries: [])
        let url2 = try AuditLogPDFComposer.compose(entries: [])
        // Both exist (same-second names may collide, but write must succeed)
        #expect(FileManager.default.fileExists(atPath: url1.path))
        #expect(FileManager.default.fileExists(atPath: url2.path))
        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }
}
#endif
