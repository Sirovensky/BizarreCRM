import Foundation

// MARK: - ExportEntity

/// Entity selection for wizard (matches server `export_type` enum).
public enum ExportEntity: String, Codable, Sendable, CaseIterable {
    case full       = "full"
    case customers  = "customers"
    case tickets    = "tickets"
    case invoices   = "invoices"
    case inventory  = "inventory"
    case expenses   = "expenses"

    public var displayName: String {
        switch self {
        case .full:      return "All data"
        case .customers: return "Customers"
        case .tickets:   return "Tickets"
        case .invoices:  return "Invoices"
        case .inventory: return "Inventory"
        case .expenses:  return "Expenses"
        }
    }

    public var systemImage: String {
        switch self {
        case .full:      return "square.and.arrow.up.on.square.fill"
        case .customers: return "person.2.fill"
        case .tickets:   return "wrench.and.screwdriver.fill"
        case .invoices:  return "doc.text.fill"
        case .inventory: return "shippingbox.fill"
        case .expenses:  return "creditcard.fill"
        }
    }
}

// MARK: - ExportFormat

public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case csv  = "csv"
    case xlsx = "xlsx"
    case json = "json"

    public var displayName: String { rawValue.uppercased() }

    public var systemImage: String {
        switch self {
        case .csv:  return "tablecells"
        case .xlsx: return "tablecells.fill"
        case .json: return "curlybraces"
        }
    }
}

// MARK: - ExportStatus (tenant async job)

public enum ExportStatus: String, Codable, Sendable, CaseIterable {
    case queued     = "queued"
    case preparing  = "preparing"
    case exporting  = "exporting"
    case encrypting = "encrypting"
    case completed  = "completed"
    case failed     = "failed"

    public var displayLabel: String {
        switch self {
        case .queued:     return "Queued"
        case .preparing:  return "Preparing…"
        case .exporting:  return "Exporting…"
        case .encrypting: return "Encrypting…"
        case .completed:  return "Ready"
        case .failed:     return "Failed"
        }
    }

    public var isTerminal: Bool {
        self == .completed || self == .failed
    }

    public var progress: Double {
        switch self {
        case .queued:     return 0.0
        case .preparing:  return 0.15
        case .exporting:  return 0.50
        case .encrypting: return 0.85
        case .completed:  return 1.0
        case .failed:     return 0.0
        }
    }
}

// MARK: - TenantExportJob (async job from POST /tenant/export)

public struct TenantExportJob: Identifiable, Codable, Sendable {
    public let id: Int
    public var status: ExportStatus
    public var startedAt: String?
    public var completedAt: String?
    public var byteSize: Int?
    public var errorMessage: String?
    public var downloadUrl: String?
    public var downloadTokenExpiresAt: String?
    public var downloadedAt: String?

    public init(
        id: Int,
        status: ExportStatus = .queued,
        startedAt: String? = nil,
        completedAt: String? = nil,
        byteSize: Int? = nil,
        errorMessage: String? = nil,
        downloadUrl: String? = nil,
        downloadTokenExpiresAt: String? = nil,
        downloadedAt: String? = nil
    ) {
        self.id = id
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.byteSize = byteSize
        self.errorMessage = errorMessage
        self.downloadUrl = downloadUrl
        self.downloadTokenExpiresAt = downloadTokenExpiresAt
        self.downloadedAt = downloadedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case startedAt            = "started_at"
        case completedAt          = "completed_at"
        case byteSize             = "byte_size"
        case errorMessage         = "error_message"
        case downloadUrl          = "download_url"
        case downloadTokenExpiresAt = "download_token_expires_at"
        case downloadedAt         = "downloaded_at"
    }
}

// MARK: - DataExportRateStatus (GET /data-export/export-all-data/status)

public struct DataExportRateStatus: Codable, Sendable {
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

    public init(
        lastExportAt: String?,
        nextAllowedInSeconds: Int,
        allowed: Bool,
        rateLimitWindowSeconds: Int
    ) {
        self.lastExportAt = lastExportAt
        self.nextAllowedInSeconds = nextAllowedInSeconds
        self.allowed = allowed
        self.rateLimitWindowSeconds = rateLimitWindowSeconds
    }
}

// MARK: - ExportSchedule (matches server data_export_schedules table)

public enum ScheduleIntervalKind: String, Codable, Sendable, CaseIterable {
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"

    public var displayName: String {
        switch self {
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

public enum ScheduleStatus: String, Codable, Sendable, CaseIterable {
    case active   = "active"
    case paused   = "paused"
    case canceled = "canceled"

    public var displayName: String {
        switch self {
        case .active:   return "Active"
        case .paused:   return "Paused"
        case .canceled: return "Canceled"
        }
    }

    public var systemImage: String {
        switch self {
        case .active:   return "checkmark.circle.fill"
        case .paused:   return "pause.circle.fill"
        case .canceled: return "xmark.circle.fill"
        }
    }
}

public struct ExportSchedule: Identifiable, Codable, Sendable {
    public let id: Int
    public var name: String
    public var exportType: ExportEntity
    public var intervalKind: ScheduleIntervalKind
    public var intervalCount: Int
    public var nextRunAt: String?
    public var deliveryEmail: String?
    public var status: ScheduleStatus
    public var createdByUsername: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case exportType            = "export_type"
        case intervalKind          = "interval_kind"
        case intervalCount         = "interval_count"
        case nextRunAt             = "next_run_at"
        case deliveryEmail         = "delivery_email"
        case status
        case createdByUsername     = "created_by_username"
    }

    public init(
        id: Int,
        name: String,
        exportType: ExportEntity,
        intervalKind: ScheduleIntervalKind,
        intervalCount: Int,
        nextRunAt: String? = nil,
        deliveryEmail: String? = nil,
        status: ScheduleStatus = .active,
        createdByUsername: String? = nil
    ) {
        self.id = id
        self.name = name
        self.exportType = exportType
        self.intervalKind = intervalKind
        self.intervalCount = intervalCount
        self.nextRunAt = nextRunAt
        self.deliveryEmail = deliveryEmail
        self.status = status
        self.createdByUsername = createdByUsername
    }
}

// MARK: - ScheduleRun (recent run record)

public struct ScheduleRun: Identifiable, Codable, Sendable {
    public let id: Int
    public let scheduleId: Int
    public let runAt: String
    public let succeeded: Bool
    public let exportFile: String?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case scheduleId    = "schedule_id"
        case runAt         = "run_at"
        case succeeded
        case exportFile    = "export_file"
        case errorMessage  = "error_message"
    }
}

// MARK: - ScheduleDetail (GET /data-export/schedules/:id response)

public struct ScheduleDetail: Codable, Sendable {
    public let schedule: ExportSchedule
    public let recentRuns: [ScheduleRun]
}

// MARK: - SettingsExport (GET /settings-ext/export.json response)

public struct SettingsExportPayload: Codable, Sendable {
    public let exportedAt: String
    public let version: Int
    public let settings: [String: String]

    enum CodingKeys: String, CodingKey {
        case exportedAt = "exported_at"
        case version
        case settings
    }
}

// MARK: - SettingsImportResult (POST /settings-ext/import response)

public struct SettingsImportResult: Codable, Sendable {
    public let imported: Int
    public let skipped: [String]
    public let total: Int
}

// MARK: - ShopTemplate (GET /settings-ext/templates response)

public struct ShopTemplate: Identifiable, Codable, Sendable {
    public let id: String
    public let label: String
    public let description: String
    public let settingsCount: Int
}

// MARK: - Legacy ExportJob (kept for ExportProgressViewModel compat while migrating)

/// Lightweight in-memory job representation used by the polling VM.
/// For tenant async jobs, the authoritative model is TenantExportJob.
public struct ExportJob: Identifiable, Codable, Sendable {
    public let id: String
    public let scope: ExportScope
    public var status: ExportStatus
    public var progressPct: Double
    public var downloadUrl: String?
    public var errorMessage: String?
    public let createdAt: Date

    public init(
        id: String,
        scope: ExportScope,
        status: ExportStatus = .queued,
        progressPct: Double = 0,
        downloadUrl: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.status = status
        self.progressPct = progressPct
        self.downloadUrl = downloadUrl
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

// MARK: - ExportScope

public enum ExportScope: String, Codable, Sendable, CaseIterable {
    case fullTenant = "fullTenant"
    case domain     = "domain"
    case customer   = "customer"

    public var displayName: String {
        switch self {
        case .fullTenant: return "Full Tenant"
        case .domain:     return "Domain"
        case .customer:   return "Customer"
        }
    }
}

// MARK: - ExportError (field error from export)

public struct ExportError: Decodable, Sendable, Identifiable {
    public var id: String { message }
    public let message: String
    public let row: String?
}

// MARK: - API request bodies

public struct StartTenantExportRequest: Encodable, Sendable {
    public let passphrase: String
    public init(passphrase: String) { self.passphrase = passphrase }
}

public struct CreateScheduleRequest: Encodable, Sendable {
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
        exportType: ExportEntity,
        intervalKind: ScheduleIntervalKind,
        intervalCount: Int,
        startDate: String,
        deliveryEmail: String? = nil
    ) {
        self.name = name
        self.exportType = exportType.rawValue
        self.intervalKind = intervalKind.rawValue
        self.intervalCount = intervalCount
        self.startDate = startDate
        self.deliveryEmail = deliveryEmail
    }
}

public struct UpdateScheduleRequest: Encodable, Sendable {
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
        exportType: ExportEntity? = nil,
        intervalKind: ScheduleIntervalKind? = nil,
        intervalCount: Int? = nil,
        deliveryEmail: String? = nil
    ) {
        self.name = name
        self.exportType = exportType?.rawValue
        self.intervalKind = intervalKind?.rawValue
        self.intervalCount = intervalCount
        self.deliveryEmail = deliveryEmail
    }
}

// MARK: - API response wrappers (server envelope: { success, data })

public struct APIEnvelope<T: Decodable>: Decodable {
    public let success: Bool
    public let data: T?
    public let message: String?
}

// MARK: - StartExportResponse (POST /tenant/export → { jobId, message })

public struct StartTenantExportResponse: Decodable, Sendable {
    public let jobId: Int
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "jobId"
        case message
    }
}

// MARK: - ExportStatusResponse (polling compat for ExportProgressViewModel)

public struct ExportStatusResponse: Decodable, Sendable {
    public let status: ExportStatus
    public let progressPct: Double
    public let downloadUrl: String?
    public let errorMessage: String?
}

// MARK: - SaveScheduleRequest (legacy compat — kept for ExportRepository protocol)

public struct SaveScheduleRequest: Encodable, Sendable {
    public let cadence: String
    public let destination: String
    public init(cadence: ExportCadence, destination: ExportDestination) {
        self.cadence = cadence.rawValue
        self.destination = destination.rawValue
    }
}

// MARK: - ExportCadence / ExportDestination (kept for ScheduledExport compat)

public enum ExportCadence: String, Codable, Sendable, CaseIterable {
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"

    public var displayName: String {
        switch self {
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

public enum ExportDestination: String, Codable, Sendable, CaseIterable {
    case icloud  = "icloud"
    case s3      = "s3"
    case dropbox = "dropbox"

    public var displayName: String {
        switch self {
        case .icloud:  return "iCloud Drive"
        case .s3:      return "Amazon S3"
        case .dropbox: return "Dropbox"
        }
    }

    public var systemImage: String {
        switch self {
        case .icloud:  return "icloud"
        case .s3:      return "cloud.fill"
        case .dropbox: return "archivebox"
        }
    }

    public var isImplemented: Bool { self == .icloud }
}

public struct ScheduledExport: Identifiable, Codable, Sendable {
    public let id: String
    public var cadence: ExportCadence
    public var destination: ExportDestination
    public var lastRunAt: Date?
    public var nextRunAt: Date?

    public init(
        id: String,
        cadence: ExportCadence,
        destination: ExportDestination,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.cadence = cadence
        self.destination = destination
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
    }
}

// MARK: - ExportScheduleDetailRaw
// Decoded from GET /data-export/schedules/:id which returns all ExportSchedule
// fields at the top level plus a "recent_runs" array embedded in the same object.

public struct ExportScheduleDetailRaw: Decodable, Sendable {
    public let schedule: ExportSchedule
    public let recentRuns: [ScheduleRun]

    public init(schedule: ExportSchedule, recentRuns: [ScheduleRun] = []) {
        self.schedule = schedule
        self.recentRuns = recentRuns
    }

    public init(from decoder: Decoder) throws {
        // Server returns a flat object: all schedule columns at the top level
        // plus "recent_runs" key for the runs array.
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let runsKey = DynamicCodingKey(stringValue: "recent_runs")!
        self.recentRuns = (try? container.decode([ScheduleRun].self, forKey: runsKey)) ?? []
        self.schedule = try ExportSchedule(from: decoder)
    }
}

/// Generic CodingKey for decoding arbitrary string keys from a JSON object.
public struct DynamicCodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int? { nil }
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { return nil }
}
