import Foundation

// MARK: - §49 Data Export API endpoints
// Routes grounded from:
//   packages/server/src/routes/dataExport.routes.ts
//   packages/server/src/routes/dataExportSchedules.routes.ts
//   packages/server/src/routes/tenantExport.routes.ts
//   packages/server/src/routes/settingsExport.routes.ts
// Envelope: { success: Bool, data: T?, message: String? }

// NOTE: The full DTO types (ExportSchedule, TenantExportJob, etc.) live in the
// DataExport package which depends on Networking. To avoid a circular dependency
// this file declares only the raw Networking-layer DTOs used for transport.
// The DataExport package re-exports typed wrappers on top of these.

// MARK: - Networking-layer DTOs

/// Raw representation of a data_export_schedules row as returned by
/// GET /api/v1/data-export/schedules and POST /api/v1/data-export/schedules.
public struct DataExportScheduleRaw: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let exportType: String
    public let intervalKind: String
    public let intervalCount: Int
    public let nextRunAt: String?
    public let deliveryEmail: String?
    public let status: String
    public let createdByUsername: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case exportType           = "export_type"
        case intervalKind         = "interval_kind"
        case intervalCount        = "interval_count"
        case nextRunAt            = "next_run_at"
        case deliveryEmail        = "delivery_email"
        case status
        case createdByUsername    = "created_by_username"
    }
}

/// Raw job status from GET /api/v1/tenant/export/:jobId.
public struct TenantExportJobRaw: Decodable, Sendable {
    public let id: Int
    public let status: String
    public let startedAt: String?
    public let completedAt: String?
    public let byteSize: Int?
    public let errorMessage: String?
    public let downloadUrl: String?
    public let downloadTokenExpiresAt: String?
    public let downloadedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case startedAt              = "started_at"
        case completedAt            = "completed_at"
        case byteSize               = "byte_size"
        case errorMessage           = "error_message"
        case downloadUrl            = "download_url"
        case downloadTokenExpiresAt = "download_token_expires_at"
        case downloadedAt           = "downloaded_at"
    }
}

/// Response from POST /api/v1/tenant/export.
public struct StartTenantExportRawResponse: Decodable, Sendable {
    public let jobId: Int
    public let message: String?
}

/// Response from GET /api/v1/data-export/export-all-data/status.
public struct DataExportRateStatusRaw: Decodable, Sendable {
    public let lastExportAt: String?
    public let nextAllowedInSeconds: Int
    public let allowed: Bool
    public let rateLimitWindowSeconds: Int

    enum CodingKeys: String, CodingKey {
        case lastExportAt           = "last_export_at"
        case nextAllowedInSeconds   = "next_allowed_in_seconds"
        case allowed
        case rateLimitWindowSeconds = "rate_limit_window_seconds"
    }
}

/// Schedule status response from pause / resume / cancel actions.
public struct ScheduleActionRaw: Decodable, Sendable {
    public let id: Int?
    public let status: String?
}

/// Settings export payload from GET /api/v1/settings-ext/export.json.
public struct SettingsExportPayloadRaw: Decodable, Sendable {
    public let exportedAt: String
    public let version: Int
    public let settings: [String: String]

    enum CodingKeys: String, CodingKey {
        case exportedAt = "exported_at"
        case version
        case settings
    }
}

/// Settings import result from POST /api/v1/settings-ext/import.
public struct SettingsImportResultRaw: Decodable, Sendable {
    public let imported: Int
    public let skipped: [String]
    public let total: Int
}

/// Shop template from GET /api/v1/settings-ext/templates.
public struct ShopTemplateRaw: Decodable, Sendable {
    public let id: String
    public let label: String
    public let description: String
    public let settingsCount: Int
}

/// GDPR PII erasure confirmation response body.
private struct PIIEraseRequestRaw: Encodable, Sendable {
    let customer_id: Int
    let confirm_name: String
}

private struct PIIEraseResponseRaw: Decodable, Sendable {
    let message: String?
}

/// Create schedule request body (snake_case keys per server validation).
public struct CreateExportScheduleBodyRaw: Encodable, Sendable {
    public let name: String
    public let exportType: String
    public let intervalKind: String
    public let intervalCount: Int
    public let startDate: String
    public let deliveryEmail: String?

    enum CodingKeys: String, CodingKey {
        case name
        case exportType    = "export_type"
        case intervalKind  = "interval_kind"
        case intervalCount = "interval_count"
        case startDate     = "start_date"
        case deliveryEmail = "delivery_email"
    }

    public init(
        name: String,
        exportType: String,
        intervalKind: String,
        intervalCount: Int,
        startDate: String,
        deliveryEmail: String? = nil
    ) {
        self.name = name
        self.exportType = exportType
        self.intervalKind = intervalKind
        self.intervalCount = intervalCount
        self.startDate = startDate
        self.deliveryEmail = deliveryEmail
    }
}

/// Partial-update schedule request body.
public struct UpdateExportScheduleBodyRaw: Encodable, Sendable {
    public let name: String?
    public let exportType: String?
    public let intervalKind: String?
    public let intervalCount: Int?
    public let deliveryEmail: String?

    enum CodingKeys: String, CodingKey {
        case name
        case exportType    = "export_type"
        case intervalKind  = "interval_kind"
        case intervalCount = "interval_count"
        case deliveryEmail = "delivery_email"
    }

    public init(
        name: String? = nil,
        exportType: String? = nil,
        intervalKind: String? = nil,
        intervalCount: Int? = nil,
        deliveryEmail: String? = nil
    ) {
        self.name = name
        self.exportType = exportType
        self.intervalKind = intervalKind
        self.intervalCount = intervalCount
        self.deliveryEmail = deliveryEmail
    }
}

private struct EmptyBodyRaw: Encodable, Sendable {}
private struct StartTenantExportBodyRaw: Encodable, Sendable {
    let passphrase: String
}
private struct SettingsImportBodyRaw: Encodable, Sendable {
    let settings: [String: String]
}
private struct ShopTemplateApplyBodyRaw: Encodable, Sendable {
    let template_id: String
}
private struct TemplateApplyResponseRaw: Decodable, Sendable {
    let templateId: String?
    let applied: Int?
    enum CodingKeys: String, CodingKey {
        case templateId = "template_id"
        case applied
    }
}

// MARK: - APIClient + Tenant Export

extension APIClient {

    /// POST /api/v1/tenant/export — start async encrypted full-tenant export job.
    /// Requires admin role + step-up TOTP (enforced server-side).
    /// Body: { passphrase: String } (≥12 chars).
    /// Returns jobId for polling via `pollTenantExportJobRaw(jobId:)`.
    public func startTenantExportJobRaw(passphrase: String) async throws -> StartTenantExportRawResponse {
        let body = StartTenantExportBodyRaw(passphrase: passphrase)
        return try await post("/tenant/export", body: body, as: StartTenantExportRawResponse.self)
    }

    /// GET /api/v1/tenant/export/:jobId — poll tenant export job status.
    /// Admin-only. Returns current status, byte_size, and download_url when complete.
    public func pollTenantExportJobRaw(jobId: Int) async throws -> TenantExportJobRaw {
        return try await get("/tenant/export/\(jobId)", as: TenantExportJobRaw.self)
    }
}

// MARK: - APIClient + Data Export (GET /data-export, POST /data-export, status)

extension APIClient {

    /// GET /api/v1/data-export/export-all-data/status
    /// Returns rate-limit window state so the UI can render "last exported at"
    /// and "next allowed in N seconds" without triggering a real export attempt.
    public func fetchDataExportRateStatusRaw() async throws -> DataExportRateStatusRaw {
        return try await get("/data-export/export-all-data/status", as: DataExportRateStatusRaw.self)
    }

    /// POST /api/v1/data-export/erase-customer-pii
    /// GDPR right-to-erasure: NULLs PII fields on the customer row.
    /// Requires admin role and confirm_name to match the customer's full name.
    public func eraseCustomerPIIRaw(customerId: Int, confirmName: String) async throws {
        let body = PIIEraseRequestRaw(customer_id: customerId, confirm_name: confirmName)
        let _: PIIEraseResponseRaw = try await post(
            "/data-export/erase-customer-pii",
            body: body,
            as: PIIEraseResponseRaw.self
        )
    }
}

// MARK: - APIClient + Export Schedules CRUD (/data-export/schedules)

extension APIClient {

    /// GET /api/v1/data-export/schedules — list all recurring export schedules.
    public func listExportSchedulesRaw() async throws -> [DataExportScheduleRaw] {
        return try await get("/data-export/schedules", as: [DataExportScheduleRaw].self)
    }

    /// POST /api/v1/data-export/schedules — create a new schedule.
    /// Required body fields: name, export_type, interval_kind, interval_count, start_date.
    /// Optional: delivery_email.
    public func createExportScheduleRaw(_ body: CreateExportScheduleBodyRaw) async throws -> DataExportScheduleRaw {
        return try await post("/data-export/schedules", body: body, as: DataExportScheduleRaw.self)
    }

    /// PATCH /api/v1/data-export/schedules/:id — partial update.
    /// All fields are optional; at least one must be provided.
    public func updateExportScheduleRaw(id: Int, body: UpdateExportScheduleBodyRaw) async throws -> DataExportScheduleRaw {
        return try await patch("/data-export/schedules/\(id)", body: body, as: DataExportScheduleRaw.self)
    }

    /// POST /api/v1/data-export/schedules/:id/pause — pause an active schedule.
    public func pauseExportScheduleRaw(id: Int) async throws {
        let _: ScheduleActionRaw = try await post(
            "/data-export/schedules/\(id)/pause",
            body: EmptyBodyRaw(),
            as: ScheduleActionRaw.self
        )
    }

    /// POST /api/v1/data-export/schedules/:id/resume — resume a paused schedule.
    public func resumeExportScheduleRaw(id: Int) async throws {
        let _: ScheduleActionRaw = try await post(
            "/data-export/schedules/\(id)/resume",
            body: EmptyBodyRaw(),
            as: ScheduleActionRaw.self
        )
    }

    /// POST /api/v1/data-export/schedules/:id/cancel — permanently cancel a schedule.
    public func cancelExportScheduleRaw(id: Int) async throws {
        let _: ScheduleActionRaw = try await post(
            "/data-export/schedules/\(id)/cancel",
            body: EmptyBodyRaw(),
            as: ScheduleActionRaw.self
        )
    }
}

// MARK: - APIClient + Settings Export (/settings-ext)

extension APIClient {

    /// GET /api/v1/settings-ext/export.json — download sanitized shop settings backup.
    /// Response is JSON attachment; secrets (API keys, SMTP passwords) are stripped server-side.
    public func fetchSettingsExportRaw() async throws -> SettingsExportPayloadRaw {
        return try await get("/settings-ext/export.json", as: SettingsExportPayloadRaw.self)
    }

    /// POST /api/v1/settings-ext/import — restore settings from a backup.
    /// Body: { settings: { key: value, ... } } or flat { key: value } object.
    /// Unknown keys and blacklisted keys are skipped; result reports counts.
    public func importSettingsRaw(settings: [String: String]) async throws -> SettingsImportResultRaw {
        let body = SettingsImportBodyRaw(settings: settings)
        return try await post("/settings-ext/import", body: body, as: SettingsImportResultRaw.self)
    }

    /// GET /api/v1/settings-ext/templates — list available shop-type templates.
    public func fetchShopTemplatesRaw() async throws -> [ShopTemplateRaw] {
        return try await get("/settings-ext/templates", as: [ShopTemplateRaw].self)
    }

    /// POST /api/v1/settings-ext/templates/apply — apply a template by ID.
    /// Applies recommended defaults for the shop type; existing settings not in
    /// the template are left unchanged.
    public func applyShopTemplateRaw(templateId: String) async throws {
        let body = ShopTemplateApplyBodyRaw(template_id: templateId)
        let _: TemplateApplyResponseRaw = try await post(
            "/settings-ext/templates/apply",
            body: body,
            as: TemplateApplyResponseRaw.self
        )
    }
}
