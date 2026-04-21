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

    private(set) var uploadCallCount = 0
    private(set) var createJobCallCount = 0
    private(set) var startCallCount = 0

    func uploadFile(data: Data, filename: String) async throws -> FileUploadResponse {
        uploadCallCount += 1
        return try uploadResult.get()
    }

    func createJob(source: ImportSource, fileId: String?, mapping: [String: String]?) async throws -> CreateImportJobResponse {
        createJobCallCount += 1
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
}

// MARK: - Fixtures

extension ImportJob {
    static func fixture(
        id: String = "job-1",
        source: ImportSource = .csv,
        status: ImportStatus = .draft,
        totalRows: Int? = 100,
        processedRows: Int = 0,
        errorCount: Int = 0
    ) -> ImportJob {
        ImportJob(
            id: id,
            source: source,
            fileId: "file-1",
            status: status,
            totalRows: totalRows,
            processedRows: processedRows,
            errorCount: errorCount,
            createdAt: Date(),
            mapping: [:]
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

    // MARK: - confirmSource

    func testConfirmSourceWithoutSourceDoesNotAdvance() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = nil
        vm.confirmSource()
        XCTAssertEqual(vm.currentStep, .chooseSource)
    }

    func testConfirmSourceWithSourceAdvancesToUpload() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource()
        XCTAssertEqual(vm.currentStep, .upload)
    }

    func testConfirmSourceSetsCorrectSource() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .repairDesk
        vm.confirmSource()
        XCTAssertEqual(vm.selectedSource, .repairDesk)
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

    // MARK: - uploadFile failure

    func testUploadFileFailureSetsErrorMessage() async {
        let repo = MockImportRepository()
        await repo.set(uploadResult: .failure(MockImportRepository.Failure.simulated))
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        vm.confirmSource() // advance to .upload first
        await vm.uploadFile(data: Data(), filename: "f.csv")
        XCTAssertNotNil(vm.errorMessage)
        // Step stays at .upload on failure
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
        await vm.uploadFile(data: Data(), filename: "f.csv") // advances to .preview
        await vm.loadPreview() // should advance to .mapping
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
        await vm.loadPreview() // auto-maps columns from fixture
        vm.confirmMapping()
        XCTAssertEqual(vm.currentStep, .start)
    }

    func testConfirmMappingWithMissingRequiredDoesNotAdvance() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.columnMapping = [:] // missing all required
        vm.confirmMapping()
        XCTAssertNotEqual(vm.currentStep, .start)
    }

    // MARK: - allRequiredMapped

    func testAllRequiredMappedFalseInitially() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertFalse(vm.allRequiredMapped)
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

    // MARK: - reset

    func testResetRestoresInitialState() async {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        vm.selectedSource = .csv
        await vm.uploadFile(data: Data(), filename: "f.csv")
        vm.reset()
        XCTAssertEqual(vm.currentStep, .chooseSource)
        XCTAssertNil(vm.selectedSource)
        XCTAssertNil(vm.jobId)
        XCTAssertNil(vm.uploadedFileId)
        XCTAssertTrue(vm.columnMapping.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - progressFraction

    func testProgressFractionZeroWhenNoJob() {
        let repo = MockImportRepository()
        let vm = ImportWizardViewModel(repository: repo)
        XCTAssertEqual(vm.progressFraction, 0.0, accuracy: 0.001)
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
}
