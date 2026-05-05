import Testing
import Foundation
@testable import DataExport

// MARK: - ExportModelsTests

@Suite("ExportModels — types, coding, and domain logic")
struct ExportModelsTests {

    // MARK: - ExportEntity

    @Test("ExportEntity.allCases includes all expected entities")
    func exportEntityAllCases() {
        let ids = ExportEntity.allCases.map { $0.rawValue }
        #expect(ids.contains("full"))
        #expect(ids.contains("customers"))
        #expect(ids.contains("tickets"))
        #expect(ids.contains("invoices"))
        #expect(ids.contains("inventory"))
        #expect(ids.contains("expenses"))
    }

    @Test("ExportEntity.full has correct displayName")
    func exportEntityFullDisplayName() {
        #expect(ExportEntity.full.displayName == "All data")
    }

    @Test("ExportEntity.customers has correct rawValue")
    func exportEntityCustomersRaw() {
        #expect(ExportEntity.customers.rawValue == "customers")
    }

    @Test("ExportEntity decodes from raw value")
    func exportEntityDecodes() throws {
        let json = #""customers""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ExportEntity.self, from: json)
        #expect(decoded == .customers)
    }

    // MARK: - ExportFormat

    @Test("ExportFormat.allCases count is 3")
    func exportFormatAllCasesCount() {
        #expect(ExportFormat.allCases.count == 3)
    }

    @Test("ExportFormat displayNames are uppercase raw values")
    func exportFormatDisplayNames() {
        #expect(ExportFormat.csv.displayName == "CSV")
        #expect(ExportFormat.xlsx.displayName == "XLSX")
        #expect(ExportFormat.json.displayName == "JSON")
    }

    // MARK: - ExportStatus

    @Test("ExportStatus.completed isTerminal")
    func completedIsTerminal() {
        #expect(ExportStatus.completed.isTerminal)
    }

    @Test("ExportStatus.failed isTerminal")
    func failedIsTerminal() {
        #expect(ExportStatus.failed.isTerminal)
    }

    @Test("ExportStatus.exporting is not terminal")
    func exportingNotTerminal() {
        #expect(!ExportStatus.exporting.isTerminal)
    }

    @Test("ExportStatus.queued has progress 0")
    func queuedProgress() {
        #expect(ExportStatus.queued.progress == 0.0)
    }

    @Test("ExportStatus.completed has progress 1")
    func completedProgress() {
        #expect(ExportStatus.completed.progress == 1.0)
    }

    @Test("ExportStatus.exporting has progress 0.5")
    func exportingProgress() {
        #expect(ExportStatus.exporting.progress == 0.50)
    }

    @Test("ExportStatus decodes from server string")
    func exportStatusDecodes() throws {
        let json = #""completed""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ExportStatus.self, from: json)
        #expect(decoded == .completed)
    }

    // MARK: - ScheduleIntervalKind

    @Test("ScheduleIntervalKind.allCases has 3 values")
    func intervalKindAllCases() {
        #expect(ScheduleIntervalKind.allCases.count == 3)
    }

    @Test("ScheduleIntervalKind decodes 'weekly' from JSON")
    func intervalKindDecodes() throws {
        let json = #""weekly""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScheduleIntervalKind.self, from: json)
        #expect(decoded == .weekly)
    }

    // MARK: - ScheduleStatus

    @Test("ScheduleStatus.active systemImage is checkmark.circle.fill")
    func activeSystemImage() {
        #expect(ScheduleStatus.active.systemImage == "checkmark.circle.fill")
    }

    @Test("ScheduleStatus.canceled systemImage is xmark.circle.fill")
    func canceledSystemImage() {
        #expect(ScheduleStatus.canceled.systemImage == "xmark.circle.fill")
    }

    // MARK: - ExportSchedule decoding

    @Test("ExportSchedule decodes from snake_case JSON")
    func exportScheduleDecodes() throws {
        let json = """
        {
          "id": 7,
          "name": "Daily all",
          "export_type": "full",
          "interval_kind": "daily",
          "interval_count": 1,
          "status": "active"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let schedule = try decoder.decode(ExportSchedule.self, from: json)
        #expect(schedule.id == 7)
        #expect(schedule.name == "Daily all")
        #expect(schedule.exportType == .full)
        #expect(schedule.intervalKind == .daily)
        #expect(schedule.intervalCount == 1)
        #expect(schedule.status == .active)
    }

    @Test("ExportSchedule decodes optional fields as nil when absent")
    func exportScheduleOptionalNil() throws {
        let json = """
        {
          "id": 1,
          "name": "A",
          "export_type": "customers",
          "interval_kind": "weekly",
          "interval_count": 2,
          "status": "paused"
        }
        """.data(using: .utf8)!

        let schedule = try JSONDecoder().decode(ExportSchedule.self, from: json)
        #expect(schedule.nextRunAt == nil)
        #expect(schedule.deliveryEmail == nil)
        #expect(schedule.createdByUsername == nil)
    }

    // MARK: - TenantExportJob decoding

    @Test("TenantExportJob decodes from server JSON")
    func tenantExportJobDecodes() throws {
        let json = """
        {
          "id": 42,
          "status": "exporting",
          "byte_size": 1024,
          "download_url": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let job = try decoder.decode(TenantExportJob.self, from: json)
        #expect(job.id == 42)
        #expect(job.status == .exporting)
        #expect(job.byteSize == 1024)
        #expect(job.downloadUrl == nil)
    }

    @Test("TenantExportJob completed status includes downloadUrl")
    func tenantExportJobCompletedDecodes() throws {
        let json = """
        {
          "id": 99,
          "status": "completed",
          "download_url": "/api/v1/tenant/export/download/abc123",
          "byte_size": 204800
        }
        """.data(using: .utf8)!

        let job = try JSONDecoder().decode(TenantExportJob.self, from: json)
        #expect(job.status == .completed)
        #expect(job.downloadUrl == "/api/v1/tenant/export/download/abc123")
    }

    // MARK: - DataExportRateStatus decoding

    @Test("DataExportRateStatus decodes allowed state")
    func rateStatusAllowedDecodes() throws {
        let json = """
        {
          "last_export_at": null,
          "next_allowed_in_seconds": 0,
          "allowed": true,
          "rate_limit_window_seconds": 3600
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(DataExportRateStatus.self, from: json)
        #expect(status.allowed == true)
        #expect(status.nextAllowedInSeconds == 0)
        #expect(status.rateLimitWindowSeconds == 3600)
        #expect(status.lastExportAt == nil)
    }

    @Test("DataExportRateStatus decodes rate-limited state")
    func rateStatusLimitedDecodes() throws {
        let json = """
        {
          "last_export_at": "2026-04-23T10:00:00Z",
          "next_allowed_in_seconds": 1800,
          "allowed": false,
          "rate_limit_window_seconds": 3600
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(DataExportRateStatus.self, from: json)
        #expect(status.allowed == false)
        #expect(status.nextAllowedInSeconds == 1800)
        #expect(status.lastExportAt == "2026-04-23T10:00:00Z")
    }

    // MARK: - SettingsExportPayload decoding

    @Test("SettingsExportPayload decodes version and settings map")
    func settingsPayloadDecodes() throws {
        let json = """
        {
          "exported_at": "2026-04-23T12:00:00Z",
          "version": 1,
          "settings": {
            "store_name": "TestShop",
            "store_timezone": "America/New_York"
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(SettingsExportPayload.self, from: json)
        #expect(payload.version == 1)
        #expect(payload.settings["store_name"] == "TestShop")
        #expect(payload.settings["store_timezone"] == "America/New_York")
    }

    // MARK: - SettingsImportResult

    @Test("SettingsImportResult decodes imported and skipped counts")
    func settingsImportResultDecodes() throws {
        let json = """
        {"imported": 5, "skipped": ["bad_key1", "bad_key2"], "total": 7}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SettingsImportResult.self, from: json)
        #expect(result.imported == 5)
        #expect(result.skipped.count == 2)
        #expect(result.total == 7)
    }

    // MARK: - CreateScheduleRequest encoding

    @Test("CreateScheduleRequest encodes snake_case keys")
    func createScheduleRequestEncodes() throws {
        let req = CreateScheduleRequest(
            name: "Daily backup",
            exportType: .customers,
            intervalKind: .daily,
            intervalCount: 1,
            startDate: "2026-04-24T00:00:00Z",
            deliveryEmail: "admin@test.com"
        )

        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["name"] as? String == "Daily backup")
        #expect(dict["export_type"] as? String == "customers")
        #expect(dict["interval_kind"] as? String == "daily")
        #expect(dict["interval_count"] as? Int == 1)
        #expect(dict["delivery_email"] as? String == "admin@test.com")
    }

    @Test("CreateScheduleRequest encodes nil delivery_email as null")
    func createScheduleRequestNilEmail() throws {
        let req = CreateScheduleRequest(
            name: "No email",
            exportType: .full,
            intervalKind: .weekly,
            intervalCount: 2,
            startDate: "2026-05-01T00:00:00Z",
            deliveryEmail: nil
        )

        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["delivery_email"] == nil || (dict["delivery_email"] is NSNull))
    }

    // MARK: - ExportScheduleDetailRaw decoding

    @Test("ExportScheduleDetailRaw decodes flat object with recent_runs")
    func scheduleDetailRawDecodes() throws {
        let json = """
        {
          "id": 5,
          "name": "Weekly invoices",
          "export_type": "invoices",
          "interval_kind": "weekly",
          "interval_count": 1,
          "status": "active",
          "recent_runs": [
            {
              "id": 101,
              "schedule_id": 5,
              "run_at": "2026-04-17T02:00:00Z",
              "succeeded": true,
              "export_file": "export_5_20260417.json",
              "error_message": null
            }
          ]
        }
        """.data(using: .utf8)!

        let raw = try JSONDecoder().decode(ExportScheduleDetailRaw.self, from: json)
        #expect(raw.schedule.id == 5)
        #expect(raw.schedule.exportType == .invoices)
        #expect(raw.recentRuns.count == 1)
        #expect(raw.recentRuns[0].succeeded == true)
    }

    @Test("ExportScheduleDetailRaw decodes when recent_runs absent")
    func scheduleDetailRawNoRuns() throws {
        let json = """
        {
          "id": 6,
          "name": "No runs",
          "export_type": "tickets",
          "interval_kind": "monthly",
          "interval_count": 1,
          "status": "paused"
        }
        """.data(using: .utf8)!

        let raw = try JSONDecoder().decode(ExportScheduleDetailRaw.self, from: json)
        #expect(raw.schedule.id == 6)
        #expect(raw.recentRuns.isEmpty)
    }
}
