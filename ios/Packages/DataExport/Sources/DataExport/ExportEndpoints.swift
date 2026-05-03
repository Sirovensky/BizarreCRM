import Foundation
import Networking

// MARK: - APIClient + Tenant Export (POST /tenant/export, GET /tenant/export/:jobId)

extension APIClient {

    /// POST /tenant/export — start async encrypted full-tenant export job.
    /// Requires admin + step-up TOTP (enforced server-side).
    /// Returns jobId so the caller can poll GET /tenant/export/:jobId.
    public func startTenantExportJob(passphrase: String) async throws -> StartTenantExportResponse {
        let req = StartTenantExportRequest(passphrase: passphrase)
        return try await post("/tenant/export", body: req, as: StartTenantExportResponse.self)
    }

    /// GET /tenant/export/:jobId — poll job status.
    public func pollTenantExportJob(jobId: Int) async throws -> TenantExportJob {
        return try await get("/tenant/export/\(jobId)", as: TenantExportJob.self)
    }

    /// GET /data-export/export-all-data/status — rate-limit window status.
    public func fetchDataExportRateStatus() async throws -> DataExportRateStatus {
        return try await get("/data-export/export-all-data/status", as: DataExportRateStatus.self)
    }

    /// POST /data-export/erase-customer-pii — GDPR right-to-erasure.
    public func eraseCustomerPII(customerId: Int, confirmName: String) async throws {
        // Use delete-style: returns success:true with no data payload.
        // We ignore the response body — any HTTP error surfaces via APITransportError.
        let _: PIIEraseResponse = try await post(
            "/data-export/erase-customer-pii",
            body: EraseCustomerPIIBody(customer_id: customerId, confirm_name: confirmName),
            as: PIIEraseResponse.self
        )
    }
}

// MARK: - APIClient + Schedule CRUD (/data-export/schedules)

extension APIClient {

    /// GET /data-export/schedules — list all schedules.
    public func listExportSchedules() async throws -> [ExportSchedule] {
        return try await get("/data-export/schedules", as: [ExportSchedule].self)
    }

    /// GET /data-export/schedules/:id — schedule detail + recent runs.
    public func getExportSchedule(id: Int) async throws -> ExportScheduleDetailRaw {
        return try await get("/data-export/schedules/\(id)", as: ExportScheduleDetailRaw.self)
    }

    /// POST /data-export/schedules — create schedule.
    public func createExportSchedule(_ request: CreateScheduleRequest) async throws -> ExportSchedule {
        return try await post("/data-export/schedules", body: request, as: ExportSchedule.self)
    }

    /// PATCH /data-export/schedules/:id — partial update.
    public func updateExportSchedule(id: Int, request: UpdateScheduleRequest) async throws -> ExportSchedule {
        return try await patch("/data-export/schedules/\(id)", body: request, as: ExportSchedule.self)
    }

    /// POST /data-export/schedules/:id/pause
    public func pauseExportSchedule(id: Int) async throws {
        let _: ScheduleStatusResponse = try await post(
            "/data-export/schedules/\(id)/pause",
            body: EmptyBody(),
            as: ScheduleStatusResponse.self
        )
    }

    /// POST /data-export/schedules/:id/resume
    public func resumeExportSchedule(id: Int) async throws {
        let _: ScheduleStatusResponse = try await post(
            "/data-export/schedules/\(id)/resume",
            body: EmptyBody(),
            as: ScheduleStatusResponse.self
        )
    }

    /// POST /data-export/schedules/:id/cancel
    public func cancelExportSchedule(id: Int) async throws {
        let _: ScheduleStatusResponse = try await post(
            "/data-export/schedules/\(id)/cancel",
            body: EmptyBody(),
            as: ScheduleStatusResponse.self
        )
    }
}

// MARK: - APIClient + Settings Export (/settings-ext)

extension APIClient {

    /// GET /settings-ext/export.json — download settings backup.
    public func fetchSettingsExport() async throws -> SettingsExportPayload {
        return try await get("/settings-ext/export.json", as: SettingsExportPayload.self)
    }

    /// POST /settings-ext/import — restore settings from a backup.
    public func importSettings(payload: [String: String]) async throws -> SettingsImportResult {
        return try await post(
            "/settings-ext/import",
            body: SettingsImportBody(settings: payload),
            as: SettingsImportResult.self
        )
    }

    /// GET /settings-ext/templates — list shop templates.
    public func fetchShopTemplates() async throws -> [ShopTemplate] {
        return try await get("/settings-ext/templates", as: [ShopTemplate].self)
    }

    /// POST /settings-ext/templates/apply — apply a template by ID.
    public func applyShopTemplate(id: String) async throws {
        let _: TemplateApplyResponse = try await post(
            "/settings-ext/templates/apply",
            body: ApplyShopTemplateBody(template_id: id),
            as: TemplateApplyResponse.self
        )
    }
}

// MARK: - Internal helpers (Encodable placeholders for void-response calls)

private struct EmptyBody: Encodable, Sendable {}

private struct EraseCustomerPIIBody: Encodable, Sendable {
    let customer_id: Int
    let confirm_name: String
}

private struct SettingsImportBody: Encodable, Sendable {
    let settings: [String: String]
}

private struct ApplyShopTemplateBody: Encodable, Sendable {
    let template_id: String
}

struct PIIEraseResponse: Decodable, Sendable {
    let message: String?
}

public struct ScheduleStatusResponse: Decodable, Sendable {
    public let id: Int?
    public let status: String?
}

struct TemplateApplyResponse: Decodable, Sendable {
    let templateId: String?
    let applied: Int?

    enum CodingKeys: String, CodingKey {
        case templateId = "template_id"
        case applied
    }
}
