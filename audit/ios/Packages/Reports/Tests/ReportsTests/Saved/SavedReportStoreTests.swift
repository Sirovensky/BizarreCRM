import XCTest
@testable import Reports

// MARK: - SavedReportStoreTests
//
// Tests:
//  - Persistence round-trip (save → reload from same UserDefaults)
//  - Ordering: newest-first
//  - Duplicate name rejection
//  - Empty name rejection
//  - Delete by ID
//  - deleteAll
//  - view(withID:) lookup
//  - Overwrite (same ID, updated name)

final class SavedReportStoreTests: XCTestCase {

    // MARK: Helpers

    /// Fresh ephemeral UserDefaults per test — no cross-test contamination.
    private func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        return ud
    }

    private func makeStore() -> SavedReportStore {
        SavedReportStore(defaults: makeDefaults())
    }

    private func makeView(
        name: String = "My View",
        kind: ReportKind = .revenue,
        dateRange: DateRangePreset = .thirtyDays,
        createdDate: Date = Date()
    ) -> SavedReportView {
        SavedReportView(
            name: name,
            reportKind: kind,
            dateRange: dateRange,
            createdDate: createdDate
        )
    }

    // MARK: - Save + all

    func test_save_viewAppearsInAll() async throws {
        let store = makeStore()
        let view = makeView(name: "Revenue Q1")
        try await store.save(view)
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, view.id)
    }

    func test_save_multipleViews_allPersisted() async throws {
        let store = makeStore()
        let v1 = makeView(name: "View A")
        let v2 = makeView(name: "View B")
        let v3 = makeView(name: "View C")
        try await store.save(v1)
        try await store.save(v2)
        try await store.save(v3)
        let all = await store.all
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Ordering (newest-first)

    func test_all_returnedNewestFirst() async throws {
        let store = makeStore()
        let older = makeView(name: "Older", createdDate: Date(timeIntervalSinceNow: -3600))
        let newer = makeView(name: "Newer", createdDate: Date())
        // Save older first
        try await store.save(older)
        try await store.save(newer)
        let all = await store.all
        XCTAssertEqual(all.first?.name, "Newer")
        XCTAssertEqual(all.last?.name, "Older")
    }

    func test_all_threeViews_newestFirst() async throws {
        let store = makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let v1 = makeView(name: "First",  createdDate: base)
        let v2 = makeView(name: "Second", createdDate: base.addingTimeInterval(60))
        let v3 = makeView(name: "Third",  createdDate: base.addingTimeInterval(120))
        try await store.save(v1)
        try await store.save(v2)
        try await store.save(v3)
        let all = await store.all
        XCTAssertEqual(all[0].name, "Third")
        XCTAssertEqual(all[1].name, "Second")
        XCTAssertEqual(all[2].name, "First")
    }

    // MARK: - Persistence round-trip

    func test_persistence_reloadsAcrossStoreInstances() async throws {
        let defaults = makeDefaults()
        let storeA = SavedReportStore(defaults: defaults)
        let view = makeView(name: "Persistent View")
        try await storeA.save(view)

        // New store instance backed by the same defaults
        let storeB = SavedReportStore(defaults: defaults)
        let all = await storeB.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Persistent View")
        XCTAssertEqual(all[0].id, view.id)
    }

    func test_persistence_fieldsRoundTrip() async throws {
        let defaults = makeDefaults()
        let storeA = SavedReportStore(defaults: defaults)
        let original = SavedReportView(
            name: "Round Trip",
            reportKind: .employees,
            dateRange: .ninetyDays,
            filters: SavedReportFilters(
                customFromDate: "2026-01-01",
                customToDate: "2026-03-31",
                extras: ["employee_id": "42"]
            ),
            createdDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await storeA.save(original)

        let storeB = SavedReportStore(defaults: defaults)
        let loaded = await storeB.all[0]
        XCTAssertEqual(loaded.name, original.name)
        XCTAssertEqual(loaded.reportKind, original.reportKind)
        XCTAssertEqual(loaded.dateRange, original.dateRange)
        XCTAssertEqual(loaded.filters, original.filters)
        XCTAssertEqual(loaded.createdDate.timeIntervalSince1970,
                       original.createdDate.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    // MARK: - Duplicate name rejection

    func test_save_duplicateName_throwsDuplicateName() async throws {
        let store = makeStore()
        try await store.save(makeView(name: "My View"))
        do {
            try await store.save(makeView(name: "My View"))
            XCTFail("Expected duplicate name error")
        } catch SavedReportStoreError.duplicateName(let name) {
            XCTAssertEqual(name, "My View")
        }
    }

    func test_save_duplicateNameCaseInsensitive_throws() async throws {
        let store = makeStore()
        try await store.save(makeView(name: "revenue q1"))
        do {
            try await store.save(makeView(name: "Revenue Q1"))
            XCTFail("Expected duplicate name error")
        } catch SavedReportStoreError.duplicateName {
            // pass
        }
    }

    func test_save_sameID_overwritesWithoutDuplicateError() async throws {
        let store = makeStore()
        let id = UUID()
        let original = SavedReportView(id: id, name: "Original",
                                       reportKind: .revenue, dateRange: .thirtyDays)
        let updated  = SavedReportView(id: id, name: "Updated",
                                       reportKind: .revenue, dateRange: .thirtyDays)
        try await store.save(original)
        try await store.save(updated)
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Updated")
    }

    // MARK: - Empty name rejection

    func test_save_emptyName_throwsEmptyName() async throws {
        let store = makeStore()
        do {
            try await store.save(makeView(name: ""))
            XCTFail("Expected empty name error")
        } catch SavedReportStoreError.emptyName {
            // pass
        }
    }

    func test_save_whitespaceOnlyName_throwsEmptyName() async throws {
        let store = makeStore()
        do {
            try await store.save(makeView(name: "   "))
            XCTFail("Expected empty name error")
        } catch SavedReportStoreError.emptyName {
            // pass
        }
    }

    // MARK: - Delete

    func test_delete_removesView() async throws {
        let store = makeStore()
        let view = makeView(name: "To Delete")
        try await store.save(view)
        await store.delete(id: view.id)
        let all = await store.all
        XCTAssertTrue(all.isEmpty)
    }

    func test_delete_nonExistentID_isNoOp() async throws {
        let store = makeStore()
        let view = makeView(name: "Keep Me")
        try await store.save(view)
        await store.delete(id: UUID()) // unknown ID
        let all = await store.all
        XCTAssertEqual(all.count, 1)
    }

    func test_delete_onlyRemovesTargetView() async throws {
        let store = makeStore()
        let keep   = makeView(name: "Keep")
        let remove = makeView(name: "Remove")
        try await store.save(keep)
        try await store.save(remove)
        await store.delete(id: remove.id)
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Keep")
    }

    // MARK: - deleteAll

    func test_deleteAll_clearsStore() async throws {
        let store = makeStore()
        try await store.save(makeView(name: "A"))
        try await store.save(makeView(name: "B"))
        await store.deleteAll()
        let all = await store.all
        XCTAssertTrue(all.isEmpty)
    }

    func test_deleteAll_persistsDeletion() async throws {
        let defaults = makeDefaults()
        let storeA = SavedReportStore(defaults: defaults)
        try await storeA.save(makeView(name: "A"))
        await storeA.deleteAll()

        let storeB = SavedReportStore(defaults: defaults)
        let all = await storeB.all
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - view(withID:)

    func test_viewWithID_returnsCorrectView() async throws {
        let store = makeStore()
        let v1 = makeView(name: "V1")
        let v2 = makeView(name: "V2")
        try await store.save(v1)
        try await store.save(v2)
        let found = await store.view(withID: v1.id)
        XCTAssertEqual(found?.name, "V1")
    }

    func test_viewWithID_unknownID_returnsNil() async throws {
        let store = makeStore()
        try await store.save(makeView(name: "V1"))
        let found = await store.view(withID: UUID())
        XCTAssertNil(found)
    }

    // MARK: - Error descriptions

    func test_emptyNameError_hasDescription() {
        let err = SavedReportStoreError.emptyName
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }

    func test_duplicateNameError_hasDescription() {
        let err = SavedReportStoreError.duplicateName("Revenue Q1")
        XCTAssertTrue(err.errorDescription?.contains("Revenue Q1") ?? false)
    }

    // MARK: - SavedReportView model

    func test_savedReportView_idStable() {
        let fixedID = UUID()
        let view = SavedReportView(id: fixedID, name: "Test",
                                   reportKind: .tickets, dateRange: .sevenDays)
        XCTAssertEqual(view.id, fixedID)
    }

    func test_savedReportView_formattedCreatedDate_nonEmpty() {
        let view = makeView()
        XCTAssertFalse(view.formattedCreatedDate.isEmpty)
    }

    func test_reportKind_allCases_haveDisplayName() {
        for kind in ReportKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind.rawValue) missing displayName")
        }
    }

    func test_reportKind_allCases_haveSystemImageName() {
        for kind in ReportKind.allCases {
            XCTAssertFalse(kind.systemImageName.isEmpty, "\(kind.rawValue) missing systemImageName")
        }
    }

    func test_savedReportFilters_emptyEquality() {
        XCTAssertEqual(SavedReportFilters.empty, SavedReportFilters())
    }

    func test_savedReportFilters_withExtras_notEqualToEmpty() {
        let f = SavedReportFilters(extras: ["key": "val"])
        XCTAssertNotEqual(f, SavedReportFilters.empty)
    }
}
