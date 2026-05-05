import XCTest
@testable import DataImport

// §48.5 Recurring Import — model + repository + viewmodel tests — agent-6 b8

final class RecurringImportTests: XCTestCase {

    // MARK: - RecurringImportSchedule model

    func test_recurringImportSchedule_init_defaultValues() {
        let s = RecurringImportSchedule()
        XCTAssertFalse(s.id.isEmpty)
        XCTAssertEqual(s.sourceType, .icloud)
        XCTAssertEqual(s.entityType, .customers)
        XCTAssertEqual(s.frequency, .daily)
        XCTAssertEqual(s.runAtHour, 2)
        XCTAssertTrue(s.isActive)
        XCTAssertNil(s.lastRunAt)
        XCTAssertNil(s.nextRunAt)
    }

    func test_recurringImportSchedule_codingKeys() throws {
        let json = """
        {
            "id": "sched-1",
            "name": "Daily customers",
            "source_type": "s3",
            "entity_type": "inventory",
            "frequency": "weekly",
            "run_at_hour": 3,
            "file_path": "s3://bucket/file.csv",
            "is_active": false,
            "last_run_status": "completed"
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(RecurringImportSchedule.self, from: json)
        XCTAssertEqual(s.id, "sched-1")
        XCTAssertEqual(s.name, "Daily customers")
        XCTAssertEqual(s.sourceType, .s3)
        XCTAssertEqual(s.entityType, .inventory)
        XCTAssertEqual(s.frequency, .weekly)
        XCTAssertEqual(s.runAtHour, 3)
        XCTAssertEqual(s.filePath, "s3://bucket/file.csv")
        XCTAssertFalse(s.isActive)
        XCTAssertEqual(s.lastRunStatus, "completed")
    }

    func test_recurringImportSchedule_encodesToCamelCaseKeys() throws {
        let s = RecurringImportSchedule(
            id: "abc",
            name: "Test",
            sourceType: .dropbox,
            entityType: .tickets,
            frequency: .hourly,
            runAtHour: 6,
            filePath: "/path/file.csv"
        )
        let data = try JSONEncoder().encode(s)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(dict["source_type"])
        XCTAssertNotNil(dict["entity_type"])
        XCTAssertNotNil(dict["run_at_hour"])
        XCTAssertNotNil(dict["file_path"])
        XCTAssertNotNil(dict["is_active"])
    }

    // MARK: - RecurringImportSourceType display names

    func test_sourceType_displayNames() {
        XCTAssertEqual(RecurringImportSourceType.s3.displayName, "Amazon S3")
        XCTAssertEqual(RecurringImportSourceType.dropbox.displayName, "Dropbox")
        XCTAssertEqual(RecurringImportSourceType.icloud.displayName, "iCloud Drive")
    }

    func test_sourceType_requiresCredentials() {
        XCTAssertTrue(RecurringImportSourceType.s3.requiresCredentials)
        XCTAssertTrue(RecurringImportSourceType.dropbox.requiresCredentials)
        XCTAssertFalse(RecurringImportSourceType.icloud.requiresCredentials)
    }

    // MARK: - RecurringImportFrequency display names

    func test_frequency_displayNames() {
        XCTAssertEqual(RecurringImportFrequency.hourly.displayName, "Every hour")
        XCTAssertEqual(RecurringImportFrequency.daily.displayName, "Daily")
        XCTAssertEqual(RecurringImportFrequency.weekly.displayName, "Weekly")
    }

    // MARK: - ImportWebhook model

    func test_importWebhook_decodesServerShape() throws {
        let json = """
        {
            "id": "wh-1",
            "inbound_url": "https://app.bizarrecrm.com/webhooks/import/wh-1",
            "entity_type": "customers",
            "is_active": true
        }
        """.data(using: .utf8)!
        let hook = try JSONDecoder().decode(ImportWebhook.self, from: json)
        XCTAssertEqual(hook.id, "wh-1")
        XCTAssertTrue(hook.inboundURL.hasPrefix("https://"))
        XCTAssertEqual(hook.entityType, .customers)
        XCTAssertTrue(hook.isActive)
    }

    // MARK: - ViewModel: startNewSchedule

    @MainActor
    func test_viewModel_startNewSchedule_opensEditor() async {
        let stub = StubRecurringImportRepository()
        let vm = RecurringImportViewModel(repository: stub)
        vm.startNewSchedule()
        XCTAssertTrue(vm.showEditor)
        XCTAssertNotNil(vm.editingSchedule)
    }

    // MARK: - ViewModel: startEditing

    @MainActor
    func test_viewModel_startEditing_setsEditingSchedule() async {
        let stub = StubRecurringImportRepository()
        let vm = RecurringImportViewModel(repository: stub)
        let sched = RecurringImportSchedule(id: "x", name: "Edit Me")
        vm.startEditing(sched)
        XCTAssertTrue(vm.showEditor)
        XCTAssertEqual(vm.editingSchedule?.id, "x")
        XCTAssertEqual(vm.editingSchedule?.name, "Edit Me")
    }

    // MARK: - ViewModel: load graceful on 404 (server stubs not yet live)

    @MainActor
    func test_viewModel_load_gracefulOnError() async {
        let stub = StubRecurringImportRepository()
        stub.listError = URLError(.notConnectedToInternet)
        let vm = RecurringImportViewModel(repository: stub)
        await vm.load()
        XCTAssertTrue(vm.schedules.isEmpty)
        XCTAssertTrue(vm.webhooks.isEmpty)
        // No error message surfaced (graceful degradation for missing server endpoint)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - ViewModel: saveSchedule (create)

    @MainActor
    func test_viewModel_saveSchedule_createsNewEntry() async {
        let stub = StubRecurringImportRepository()
        let vm = RecurringImportViewModel(repository: stub)
        let s = RecurringImportSchedule(id: "new-1", name: "New Schedule")
        stub.createResult = s
        await vm.saveSchedule(s)
        XCTAssertEqual(vm.schedules.count, 1)
        XCTAssertEqual(vm.schedules.first?.id, "new-1")
        XCTAssertFalse(vm.showEditor)
    }

    // MARK: - ViewModel: deleteSchedule

    @MainActor
    func test_viewModel_deleteSchedule_removesFromList() async {
        let stub = StubRecurringImportRepository()
        let vm = RecurringImportViewModel(repository: stub)
        let s = RecurringImportSchedule(id: "del-1", name: "To Delete")
        stub.createResult = s
        await vm.saveSchedule(s)
        XCTAssertEqual(vm.schedules.count, 1)
        await vm.deleteSchedule(id: "del-1")
        XCTAssertTrue(vm.schedules.isEmpty)
    }
}

// MARK: - StubRecurringImportRepository

final class StubRecurringImportRepository: RecurringImportRepository, @unchecked Sendable {
    var listError: Error?
    var createResult: RecurringImportSchedule = RecurringImportSchedule()
    var updateResult: RecurringImportSchedule = RecurringImportSchedule()
    var runJobId: String? = "job-1"

    private var stored: [RecurringImportSchedule] = []

    func listSchedules() async throws -> [RecurringImportSchedule] {
        if let err = listError { throw err }
        return stored
    }

    func createSchedule(_ s: RecurringImportSchedule) async throws -> RecurringImportSchedule {
        stored.append(createResult)
        return createResult
    }

    func updateSchedule(_ s: RecurringImportSchedule) async throws -> RecurringImportSchedule {
        if let idx = stored.firstIndex(where: { $0.id == s.id }) {
            stored[idx] = s
        }
        return s
    }

    func deleteSchedule(id: String) async throws {
        stored.removeAll { $0.id == id }
    }

    func runNow(id: String) async throws -> String? {
        return runJobId
    }

    func listWebhooks() async throws -> [ImportWebhook] {
        if let err = listError { throw err }
        return []
    }

    func createWebhook(_ w: ImportWebhook) async throws -> ImportWebhook {
        return w
    }
}
