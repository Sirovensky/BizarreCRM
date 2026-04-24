import XCTest
@testable import DataImport

// MARK: - Mock repository

actor MockImportRepository: ImportRepository {
    enum Failure: Error, LocalizedError {
        case simulated
        var errorDescription: String? { "Simulated error" }
    }

    var uploadResult: Result<FileUploadResponse, Error> = .success(.init(fileId: "file-1"))
    var createJobResult: Result<CreateImportJobResponse, Error> = .success(.init(importId: "job-1", status: "draft"))
    var getJobResult: Result<ImportJob, Error> = .success(.fixture())
    var previewResult: Result<ImportPreview, Error> = .success(.fixture())
    var startResult: Result<ImportJob, Error> = .success(.fixture(status: .running))
    var errorsResult: Result<[ImportRowError], Error> = .success([])
    var listResult: Result<[ImportJob], Error> = .success([.fixture()])
    var rollbackResult: Result<RollbackImportResponse, Error> = .success(.init(message: "Rolled back"))

    private(set) var uploadCallCount = 0
    private(set) var createJobCallCount = 0
    private(set) var startCallCount = 0
    private(set) var rollbackCallCount = 0
    private(set) var lastEntityType: ImportEntityType = .customers

    func uploadFile(data: Data, filename: String) async throws -> FileUploadResponse {
        uploadCallCount += 1
        return try uploadResult.get()
    }

    func createJob(source: ImportSource, entityType: ImportEntityType, fileId: String?, mapping: [String: String]?) async throws -> CreateImportJobResponse {
        createJobCallCount += 1
        lastEntityType = entityType
        return try createJobResult.get()
    }

    func getJob(id: String) async throws -> ImportJob {
        return try getJobResult.get()
    }

    func getPreview(id: String) async throws -> ImportPreview {
        return try previewResult.get()
    }

    func startJob(id: String) async throws -> ImportJob {
        startCallCount += 1
        return try startResult.get()
    }

    func getErrors(id: String) async throws -> [ImportRowError] {
        return try errorsResult.get()
    }

    func listJobs() async throws -> [ImportJob] {
        return try listResult.get()
    }

    func rollbackJob(id: String) async throws -> RollbackImportResponse {
        rollbackCallCount += 1
        return try rollbackResult.get()
    }
}

// MARK: - Fixtures

extension ImportJob {
    static func fixture(
        id: String = "job-1",
        source: ImportSource = .csv,
        entityType: ImportEntityType = .customers,
        status: ImportStatus = .draft,
        totalRows: Int? = 100,
        processedRows: Int = 0,
        errorCount: Int = 0,
        rollbackAvailableUntil: Date? = nil
    ) -> ImportJob {
        ImportJob(
            id: id,
            source: source,
            entityType: entityType,
            fileId: "file-1",
            status: status,
            totalRows: totalRows,
            processedRows: processedRows,
            errorCount: errorCount,
            createdAt: Date(),
            mapping: [:],
            rollbackAvailableUntil: rollbackAvailableUntil
        )
    }

    static func completedWithRollback() -> ImportJob {
        ImportJob(
            id: "job-rb",
            source: .csv,
            entityType: .customers,
            fileId: "file-1",
            status: .completed,
            totalRows: 50,
            processedRows: 50,
            errorCount: 0,
            createdAt: Date(),
            mapping: [:],
            rollbackAvailableUntil: Date().addingTimeInterval(3600)
        )
    }
}

extension ImportPreview {
    static func fixture(
        columns: [String] = ["first_name", "last_name", "email", "phone"],
        rows: [[String]] = [["Alice", "Smith", "a@x.com", "555-0001"]],
        totalRows: Int = 5
    ) -> ImportPreview {
        ImportPreview(columns: columns, rows: rows, totalRows: totalRows)
    }

    static func inventoryFixture() -> ImportPreview {
        ImportPreview(
            columns: ["name", "sku", "price", "quantity"],
            rows: [["Widget", "WGT-001", "9.99", "10"]],
            totalRows: 3
        )
    }
}

// MARK: - Tests

@MainActor
final class ImportWizardViewModelTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStepIsChooseSource() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertEqual(vm.currentStep, .chooseSource)
    }

    func testInitiallyNotLoading() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertFalse(vm.isLoading)
    }

    func testInitiallyNoError() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertNil(vm.errorMessage)
    }

    func testDefaultEntityIsCustomers() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertEqual(vm.selectedEntity, .customers)
    }

    // MARK: - confirmSource

    func testConfirmSourceWithoutSourceDoesNotAdvance() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = nil
        vm.confirmSource()
        XCTAssertEqual(vm.currentStep, .chooseSource)
    }

    func testConfirmSourceAdvancesToChooseEntity() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource()
        XCTAssertEqual(vm.currentStep, .chooseEntity)
    }

    // MARK: - confirmEntity

    func testConfirmEntityAdvancesToUpload() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource() // -> .chooseEntity
        vm.confirmEntity() // -> .upload
        XCTAssertEqual(vm.currentStep, .upload)
    }

    func testConfirmEntityPreservesSelection() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedEntity = .inventory
        vm.selectedSource = .csv
        vm.confirmSource()
        vm.confirmEntity()
        XCTAssertEqual(vm.selectedEntity, .inventory)
    }

    // MARK: - uploadFile success

    func testUploadFileAdvancesToPreview() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data("a,b".utf8), filename: "test.csv")
        XCTAssertEqual(vm.currentStep, .preview)
    }

    func testUploadFileStoresJobId() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "test.csv")
        XCTAssertEqual(vm.jobId, "job-1")
    }

    func testUploadFileStoresFileId() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "test.csv")
        XCTAssertEqual(vm.uploadedFileId, "file-1")
    }

    func testUploadFileCallsUploadOnce() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        let count = await repo.uploadCallCount
        XCTAssertEqual(count, 1)
    }

    func testUploadFileSendsEntityType() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.selectedEntity = .inventory
        await vm.uploadFile(data: Data(), filename: "f.csv")
        let entityType = await repo.lastEntityType
        XCTAssertEqual(entityType, .inventory)
    }

    // MARK: - uploadFile failure

    func testUploadFileFailureSetsErrorMessage() async {
        let repo = MockImportRepository()
        await repo.set(uploadResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource()
        vm.confirmEntity()
        await vm.uploadFile(data: Data(), filename: "f.csv")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.currentStep, .upload)
    }

    func testUploadFileFailureResetsProgress() async {
        let repo = MockImportRepository()
        await repo.set(uploadResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        XCTAssertEqual(vm.uploadProgress, 0.0, accuracy: 0.001)
    }

    // MARK: - loadPreview success

    func testLoadPreviewAdvancesToMapping() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        XCTAssertEqual(vm.currentStep, .mapping)
    }

    func testLoadPreviewSetsPreviewData() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        XCTAssertNotNil(vm.preview)
        XCTAssertEqual(vm.preview?.columns, ["first_name", "last_name", "email", "phone"])
    }

    func testLoadPreviewAutoMapsColumns() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        XCTAssertFalse(vm.columnMapping.isEmpty)
        XCTAssertEqual(vm.columnMapping["first_name"], CRMField.firstName.rawValue)
    }

    func testLoadPreviewAutoMapsInventoryColumns() async {
        let repo = MockImportRepository()
        await repo.set(previewResult: .success(.inventoryFixture()))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.selectedEntity = .inventory
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        // "name" should map to inventory.name
        XCTAssertEqual(vm.columnMapping["name"], CRMField.itemName.rawValue)
        // "sku" should map to inventory.sku
        XCTAssertEqual(vm.columnMapping["sku"], CRMField.itemSku.rawValue)
    }

    // MARK: - loadPreview failure

    func testLoadPreviewFailureSetsError() async {
        let repo = MockImportRepository()
        await repo.set(previewResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - confirmMapping

    func testConfirmMappingWithAllRequiredAdvancesToStart() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        vm.confirmMapping()
        XCTAssertEqual(vm.currentStep, .start)
    }

    func testConfirmMappingWithMissingRequiredDoesNotAdvance() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.columnMapping = [:]
        vm.confirmMapping()
        XCTAssertNotEqual(vm.currentStep, .start)
    }

    // MARK: - allRequiredMapped

    func testAllRequiredMappedFalseInitially() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertFalse(vm.allRequiredMapped)
    }

    func testAllRequiredMappedForInventory() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedEntity = .inventory
        vm.columnMapping = [
            "name": CRMField.itemName.rawValue,
            "sku":  CRMField.itemSku.rawValue
        ]
        XCTAssertTrue(vm.allRequiredMapped)
    }

    func testAllRequiredMappedForTickets() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedEntity = .tickets
        vm.columnMapping = [
            "device":  CRMField.ticketDevice.rawValue,
            "problem": CRMField.ticketProblem.rawValue
        ]
        XCTAssertTrue(vm.allRequiredMapped)
    }

    // MARK: - startImport success

    func testStartImportAdvancesToProgress() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        vm.confirmMapping()
        await vm.startImport()
        XCTAssertEqual(vm.currentStep, .progress)
    }

    func testStartImportCallsStartOnce() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        vm.confirmMapping()
        await vm.startImport()
        let count = await repo.startCallCount
        XCTAssertEqual(count, 1)
    }

    func testStartImportInitializesCheckpoint() async {
        let repo = MockImportRepository()
        await repo.set(startResult: .success(.fixture(status: .running, totalRows: 200)))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        vm.confirmMapping()
        await vm.startImport()
        XCTAssertNotNil(vm.checkpoint)
        XCTAssertEqual(vm.checkpoint?.totalRows, 200)
        XCTAssertEqual(vm.checkpoint?.nextChunkIndex, 0)
    }

    // MARK: - startImport failure

    func testStartImportFailureSetsError() async {
        let repo = MockImportRepository()
        await repo.set(startResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.loadPreview()
        vm.confirmMapping()
        await vm.startImport()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNotEqual(vm.currentStep, .progress)
    }

    // MARK: - viewErrors

    func testViewErrorsTransitionsToErrors() async {
        let repo = MockImportRepository()
        await repo.set(errorsResult: .success([ImportRowError(row: 1, column: "email", reason: "Invalid format")]))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.viewErrors()
        XCTAssertEqual(vm.currentStep, .errors)
    }

    func testViewErrorsLoadsErrors() async {
        let repo = MockImportRepository()
        await repo.set(errorsResult: .success([
            ImportRowError(row: 5, column: "phone", reason: "Missing value"),
            ImportRowError(row: 10, column: nil, reason: "Duplicate")
        ]))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        await vm.viewErrors()
        XCTAssertEqual(vm.rowErrors.count, 2)
    }

    // MARK: - rollback

    func testRollbackCallsRepositoryWhenCanRollback() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        // Simulate job with canRollback = true
        vm.job = .completedWithRollback()
        vm.jobId = "job-rb"
        await vm.rollback()
        let count = await repo.rollbackCallCount
        XCTAssertEqual(count, 1)
    }

    func testRollbackDoesNotCallRepositoryWhenCannotRollback() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        // No job set / canRollback = false
        await vm.rollback()
        let count = await repo.rollbackCallCount
        XCTAssertEqual(count, 0)
    }

    func testRollbackSetsRolledBackStatus() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        vm.job = .completedWithRollback()
        vm.jobId = "job-rb"
        await vm.rollback()
        XCTAssertEqual(vm.job?.status, .rolledBack)
    }

    func testRollbackSetsRollbackMessage() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.job = .completedWithRollback()
        vm.jobId = "job-rb"
        await vm.rollback()
        XCTAssertNotNil(vm.rollbackMessage)
    }

    func testRollbackFailureSetsMessage() async {
        let repo = MockImportRepository()
        await repo.set(rollbackResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportWizardViewModel(repository: repo)
        vm.job = .completedWithRollback()
        vm.jobId = "job-rb"
        await vm.rollback()
        XCTAssertNotNil(vm.rollbackMessage)
        XCTAssertFalse(vm.isRollingBack)
    }

    // MARK: - reset

    func testResetRestoresInitialState() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.selectedEntity = .inventory
        await vm.uploadFile(data: Data(), filename: "f.csv")
        vm.reset()
        XCTAssertEqual(vm.currentStep, .chooseSource)
        XCTAssertNil(vm.selectedSource)
        XCTAssertEqual(vm.selectedEntity, .customers)
        XCTAssertNil(vm.jobId)
        XCTAssertNil(vm.uploadedFileId)
        XCTAssertTrue(vm.columnMapping.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.checkpoint)
    }

    // MARK: - progressFraction

    func testProgressFractionZeroWhenNoJob() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertEqual(vm.progressFraction, 0.0, accuracy: 0.001)
    }

    func testProgressFractionUsesCheckpoint() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.checkpoint = ImportCheckpoint(jobId: "j", totalRows: 100, nextChunkIndex: 5, chunkSize: 10)
        // 5 chunks done out of 10 total = 0.5
        XCTAssertEqual(vm.progressFraction, 0.5, accuracy: 0.01)
    }

    func testProgressFractionFallsBackToJobRows() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.job = .fixture(status: .running, totalRows: 100, processedRows: 25)
        // No checkpoint; falls back to processedRows / totalRows
        XCTAssertEqual(vm.progressFraction, 0.25, accuracy: 0.01)
    }
}

// MARK: - MockImportRepository helpers

extension MockImportRepository {
    func set(uploadResult: Result<FileUploadResponse, Error>) {
        self.uploadResult = uploadResult
    }
    func set(createJobResult: Result<CreateImportJobResponse, Error>) {
        self.createJobResult = createJobResult
    }
    func set(previewResult: Result<ImportPreview, Error>) {
        self.previewResult = previewResult
    }
    func set(startResult: Result<ImportJob, Error>) {
        self.startResult = startResult
    }
    func set(errorsResult: Result<[ImportRowError], Error>) {
        self.errorsResult = errorsResult
    }
    func set(rollbackResult: Result<RollbackImportResponse, Error>) {
        self.rollbackResult = rollbackResult
    }
}

// ImportWizardViewModel.job, .jobId, .checkpoint are internal(set) so tests can assign directly.
