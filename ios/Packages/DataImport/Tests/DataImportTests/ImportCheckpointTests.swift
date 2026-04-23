import XCTest
@testable import DataImport

// MARK: - ImportCheckpointTests

final class ImportCheckpointTests: XCTestCase {

    // MARK: - totalChunks

    func testTotalChunksExact() {
        let cp = ImportCheckpoint(jobId: "j", totalRows: 100, chunkSize: 10)
        XCTAssertEqual(cp.totalChunks, 10)
    }

    func testTotalChunksRoundsUp() {
        let cp = ImportCheckpoint(jobId: "j", totalRows: 105, chunkSize: 10)
        XCTAssertEqual(cp.totalChunks, 11)
    }

    func testTotalChunksSingleRow() {
        let cp = ImportCheckpoint(jobId: "j", totalRows: 1, chunkSize: 100)
        XCTAssertEqual(cp.totalChunks, 1)
    }

    func testTotalChunksZeroRows() {
        let cp = ImportCheckpoint(jobId: "j", totalRows: 0, chunkSize: 100)
        // max(1, ...) means at least 1
        XCTAssertEqual(cp.totalChunks, 1)
    }

    // MARK: - isComplete

    func testIsCompleteWhenNextIndexEqualsTotal() {
        var cp = ImportCheckpoint(jobId: "j", totalRows: 100, chunkSize: 10)
        cp.nextChunkIndex = 10
        XCTAssertTrue(cp.isComplete)
    }

    func testIsCompleteWhenNextIndexBeyondTotal() {
        var cp = ImportCheckpoint(jobId: "j", totalRows: 100, chunkSize: 10)
        cp.nextChunkIndex = 12
        XCTAssertTrue(cp.isComplete)
    }

    func testIsNotCompleteWhenPartiallyDone() {
        var cp = ImportCheckpoint(jobId: "j", totalRows: 100, chunkSize: 10)
        cp.nextChunkIndex = 5
        XCTAssertFalse(cp.isComplete)
    }

    func testIsNotCompleteAtStart() {
        let cp = ImportCheckpoint(jobId: "j", totalRows: 100)
        XCTAssertFalse(cp.isComplete)
    }

    // MARK: - progressFraction

    func testProgressFractionZeroAtStart() {
        let cp = ImportCheckpoint(jobId: "j", totalRows: 100)
        XCTAssertEqual(cp.progressFraction, 0.0, accuracy: 0.001)
    }

    func testProgressFractionHalfway() {
        var cp = ImportCheckpoint(jobId: "j", totalRows: 100, chunkSize: 10)
        cp.nextChunkIndex = 5
        XCTAssertEqual(cp.progressFraction, 0.5, accuracy: 0.01)
    }

    func testProgressFractionComplete() {
        var cp = ImportCheckpoint(jobId: "j", totalRows: 100, chunkSize: 10)
        cp.nextChunkIndex = 10
        XCTAssertEqual(cp.progressFraction, 1.0, accuracy: 0.001)
    }

    func testProgressFractionCapsAtOne() {
        var cp = ImportCheckpoint(jobId: "j", totalRows: 100, chunkSize: 10)
        cp.nextChunkIndex = 15 // beyond end
        XCTAssertLessThanOrEqual(cp.progressFraction, 1.0)
    }

    // MARK: - Default chunkSize

    func testDefaultChunkSizeIs100() {
        let cp = ImportCheckpoint(jobId: "j", totalRows: 500)
        XCTAssertEqual(cp.chunkSize, 100)
    }

    // MARK: - Codable round-trip

    func testCheckpointCodableRoundTrip() throws {
        let original = ImportCheckpoint(
            jobId: "abc-123",
            totalRows: 200,
            nextChunkIndex: 3,
            chunkSize: 50,
            lastUpdated: Date(timeIntervalSinceReferenceDate: 0)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImportCheckpoint.self, from: data)
        XCTAssertEqual(decoded.jobId, original.jobId)
        XCTAssertEqual(decoded.totalRows, original.totalRows)
        XCTAssertEqual(decoded.nextChunkIndex, original.nextChunkIndex)
        XCTAssertEqual(decoded.chunkSize, original.chunkSize)
    }
}

// MARK: - ImportColumnMapperMultiEntityTests

final class ImportColumnMapperMultiEntityTests: XCTestCase {

    // MARK: - Inventory auto-map

    func testAutoMapInventoryName() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["name"], entity: .inventory)
        XCTAssertEqual(mapping["name"], CRMField.itemName.rawValue)
    }

    func testAutoMapInventorySKU() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["sku"], entity: .inventory)
        XCTAssertEqual(mapping["sku"], CRMField.itemSku.rawValue)
    }

    func testAutoMapInventoryPrice() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["price"], entity: .inventory)
        XCTAssertEqual(mapping["price"], CRMField.itemPrice.rawValue)
    }

    func testAutoMapInventoryQuantity() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["quantity"], entity: .inventory)
        XCTAssertEqual(mapping["quantity"], CRMField.itemQty.rawValue)
    }

    func testAutoMapInventoryDoesNotMatchCustomerFields() {
        // "first_name" should not map to anything in inventory context
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["first_name"], entity: .inventory)
        // first_name is a customer field, should not appear in inventory mapping
        if let v = mapping["first_name"] {
            XCTAssertFalse(v.hasPrefix("customer."), "Should not map customer field in inventory context")
        }
    }

    // MARK: - Tickets auto-map

    func testAutoMapTicketDevice() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["device"], entity: .tickets)
        XCTAssertEqual(mapping["device"], CRMField.ticketDevice.rawValue)
    }

    func testAutoMapTicketProblem() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["problem"], entity: .tickets)
        XCTAssertEqual(mapping["problem"], CRMField.ticketProblem.rawValue)
    }

    func testAutoMapTicketCustomerName() {
        let mapping = ImportColumnMapper.autoMap(sourceColumns: ["customer_name"], entity: .tickets)
        XCTAssertEqual(mapping["customer_name"], CRMField.ticketCustomerName.rawValue)
    }

    // MARK: - allRequiredMapped per entity

    func testAllRequiredMappedForInventory_true() {
        let mapping = [
            "n": CRMField.itemName.rawValue,
            "s": CRMField.itemSku.rawValue
        ]
        XCTAssertTrue(ImportColumnMapper.allRequiredMapped(mapping, entity: .inventory))
    }

    func testAllRequiredMappedForInventory_false_missingSku() {
        let mapping = ["n": CRMField.itemName.rawValue]
        XCTAssertFalse(ImportColumnMapper.allRequiredMapped(mapping, entity: .inventory))
    }

    func testAllRequiredMappedForTickets_true() {
        let mapping = [
            "d": CRMField.ticketDevice.rawValue,
            "p": CRMField.ticketProblem.rawValue
        ]
        XCTAssertTrue(ImportColumnMapper.allRequiredMapped(mapping, entity: .tickets))
    }

    func testAllRequiredMappedForTickets_false_missingProblem() {
        let mapping = ["d": CRMField.ticketDevice.rawValue]
        XCTAssertFalse(ImportColumnMapper.allRequiredMapped(mapping, entity: .tickets))
    }

    // MARK: - missingRequired per entity

    func testMissingRequiredForInventory_allMissing() {
        let missing = ImportColumnMapper.missingRequired([:], entity: .inventory)
        XCTAssertTrue(missing.contains(.itemName))
        XCTAssertTrue(missing.contains(.itemSku))
    }

    func testMissingRequiredForInventory_onlySkuMissing() {
        let mapping = ["n": CRMField.itemName.rawValue]
        let missing = ImportColumnMapper.missingRequired(mapping, entity: .inventory)
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first, .itemSku)
    }

    func testMissingRequiredForTickets_noneWhenAllMapped() {
        let mapping = [
            "a": CRMField.ticketDevice.rawValue,
            "b": CRMField.ticketProblem.rawValue
        ]
        XCTAssertTrue(ImportColumnMapper.missingRequired(mapping, entity: .tickets).isEmpty)
    }

    // MARK: - CRMField entity categorization

    func testCustomerFieldsHaveCorrectEntity() {
        XCTAssertEqual(CRMField.firstName.entityType, .customers)
        XCTAssertEqual(CRMField.phone.entityType, .customers)
        XCTAssertEqual(CRMField.email.entityType, .customers)
    }

    func testInventoryFieldsHaveCorrectEntity() {
        XCTAssertEqual(CRMField.itemName.entityType, .inventory)
        XCTAssertEqual(CRMField.itemSku.entityType, .inventory)
        XCTAssertEqual(CRMField.itemPrice.entityType, .inventory)
    }

    func testTicketFieldsHaveCorrectEntity() {
        XCTAssertEqual(CRMField.ticketDevice.entityType, .tickets)
        XCTAssertEqual(CRMField.ticketProblem.entityType, .tickets)
        XCTAssertEqual(CRMField.ticketStatus.entityType, .tickets)
    }

    func testFieldsForEntityReturnsOnlyThatEntityFields() {
        let customerFields = CRMField.fields(for: .customers)
        XCTAssertTrue(customerFields.allSatisfy { $0.entityType == .customers })

        let inventoryFields = CRMField.fields(for: .inventory)
        XCTAssertTrue(inventoryFields.allSatisfy { $0.entityType == .inventory })

        let ticketFields = CRMField.fields(for: .tickets)
        XCTAssertTrue(ticketFields.allSatisfy { $0.entityType == .tickets })
    }

    func testRequiredFieldsForInventory() {
        let required = CRMField.requiredFields(for: .inventory)
        XCTAssertTrue(required.contains(.itemName))
        XCTAssertTrue(required.contains(.itemSku))
        XCTAssertFalse(required.contains(.itemPrice)) // price is optional
    }

    func testRequiredFieldsForTickets() {
        let required = CRMField.requiredFields(for: .tickets)
        XCTAssertTrue(required.contains(.ticketDevice))
        XCTAssertTrue(required.contains(.ticketProblem))
    }

    // MARK: - Normalize strips multiple prefixes

    func testNormalizeStripsInventoryPrefix() {
        XCTAssertEqual(ImportColumnMapper.normalize("inventory.name"), "name")
    }

    func testNormalizeStripsTicketPrefix() {
        XCTAssertEqual(ImportColumnMapper.normalize("ticket.device"), "device")
    }

    func testNormalizeStripsCustomerPrefix() {
        XCTAssertEqual(ImportColumnMapper.normalize("customer.first_name"), "firstname")
    }
}

// MARK: - ImportJobCanRollbackTests

final class ImportJobCanRollbackTests: XCTestCase {

    func testCanRollbackWhenCompletedAndWithinWindow() {
        let job = ImportJob.completedWithRollback()
        XCTAssertTrue(job.canRollback)
    }

    func testCannotRollbackWhenWindowExpired() {
        var job = ImportJob.completedWithRollback()
        job = ImportJob(
            id: job.id,
            source: job.source,
            entityType: job.entityType,
            fileId: job.fileId,
            status: .completed,
            totalRows: job.totalRows,
            processedRows: job.processedRows,
            errorCount: job.errorCount,
            createdAt: job.createdAt,
            mapping: job.mapping,
            rollbackAvailableUntil: Date().addingTimeInterval(-3600) // expired
        )
        XCTAssertFalse(job.canRollback)
    }

    func testCannotRollbackWhenStatusNotCompleted() {
        let job = ImportJob.fixture(
            status: .running,
            rollbackAvailableUntil: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(job.canRollback)
    }

    func testCannotRollbackWhenAlreadyRolledBack() {
        let job = ImportJob.fixture(
            status: .rolledBack,
            rollbackAvailableUntil: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(job.canRollback)
    }

    func testCannotRollbackWhenNilWindow() {
        let job = ImportJob.fixture(status: .completed, rollbackAvailableUntil: nil)
        XCTAssertFalse(job.canRollback)
    }
}
