import Foundation
import Testing
@testable import Hardware

// MARK: - PDFArchiveServiceTests
//
// §17.4 — Archival: generated PDFs on tenant server (primary) + local cache (offline).

@Suite("PDFArchiveService")
struct PDFArchiveServiceTests {

    // MARK: - archive

    @Test("archive copies file to AppSupport and returns entry")
    func archiveCopiesFile() async throws {
        let svc = PDFArchiveService()

        // Create a temporary source PDF.
        let srcURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pdf")
        let sampleData = Data("PDF-stub".utf8)
        try sampleData.write(to: srcURL)
        defer { try? FileManager.default.removeItem(at: srcURL) }

        let entry = try await svc.archive(
            srcURL,
            entityKind: "invoice",
            entityId: "INV-TEST-001",
            documentType: "Invoice"
        )

        #expect(entry.entityKind == "invoice")
        #expect(entry.entityId == "INV-TEST-001")
        #expect(entry.documentType == "Invoice")
        #expect(entry.uploadedAt == nil, "Should not be marked uploaded yet")

        // Verify local file exists.
        let localURL = await svc.localURL(for: entry.id)
        #expect(localURL != nil, "Archived file should be accessible locally")

        // Cleanup.
        await svc.delete(entryId: entry.id)
    }

    @Test("archive throws fileMissing when source does not exist")
    func archiveThrowsWhenSourceMissing() async {
        let svc = PDFArchiveService()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).pdf")

        await #expect(throws: PDFArchiveError.self) {
            try await svc.archive(
                missingURL,
                entityKind: "receipt",
                entityId: "REC-000",
                documentType: "Receipt"
            )
        }
    }

    // MARK: - entries

    @Test("entries returns all entries for entity, newest first")
    func entriesOrderedNewestFirst() async throws {
        let svc = PDFArchiveService()
        let srcURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pdf")
        try Data("stub".utf8).write(to: srcURL)
        defer { try? FileManager.default.removeItem(at: srcURL) }

        let e1 = try await svc.archive(srcURL, entityKind: "ticket", entityId: "TKT-42", documentType: "Work Order")
        let e2 = try await svc.archive(srcURL, entityKind: "ticket", entityId: "TKT-42", documentType: "Work Order")
        let list = await svc.entries(entityKind: "ticket", entityId: "TKT-42")

        #expect(list.count >= 2)
        // Newest first.
        if list.count >= 2 {
            #expect(list[0].createdAt >= list[1].createdAt)
        }
        await svc.delete(entryId: e1.id)
        await svc.delete(entryId: e2.id)
    }

    // MARK: - markUploaded

    @Test("markUploaded sets uploadedAt and serverDocumentId")
    func markUploadedSetsFields() async throws {
        let svc = PDFArchiveService()
        let srcURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pdf")
        try Data("stub".utf8).write(to: srcURL)
        defer { try? FileManager.default.removeItem(at: srcURL) }

        let entry = try await svc.archive(srcURL, entityKind: "receipt", entityId: "REC-99", documentType: "Receipt")
        await svc.markUploaded(entryId: entry.id, serverDocumentId: "srv-doc-123")

        let updated = await svc.entries(entityKind: "receipt", entityId: "REC-99")
            .first(where: { $0.id == entry.id })
        #expect(updated?.uploadedAt != nil)
        #expect(updated?.serverDocumentId == "srv-doc-123")

        await svc.delete(entryId: entry.id)
    }

    // MARK: - pendingUploadEntries

    @Test("pendingUploadEntries excludes uploaded entries")
    func pendingExcludesUploaded() async throws {
        let svc = PDFArchiveService()
        let srcURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pdf")
        try Data("stub".utf8).write(to: srcURL)
        defer { try? FileManager.default.removeItem(at: srcURL) }

        let pending = try await svc.archive(srcURL, entityKind: "receipt", entityId: "REC-PEND", documentType: "Receipt")
        let uploaded = try await svc.archive(srcURL, entityKind: "receipt", entityId: "REC-PEND", documentType: "Receipt")
        await svc.markUploaded(entryId: uploaded.id, serverDocumentId: "srv-456")

        let pendingList = await svc.pendingUploadEntries
        let ids = pendingList.map(\.id)
        #expect(ids.contains(pending.id))
        #expect(!ids.contains(uploaded.id))

        await svc.delete(entryId: pending.id)
        await svc.delete(entryId: uploaded.id)
    }

    // MARK: - PrintMedium margin

    @Test("PrintMedium letter margin is 36 points")
    func printMediumLetterMargin() {
        #expect(PrintMedium.letter.margin == 36)
    }

    @Test("PrintMedium thermal80mm margin is 4 points")
    func printMediumThermalMargin() {
        #expect(PrintMedium.thermal80mm.margin == 4)
    }
}
