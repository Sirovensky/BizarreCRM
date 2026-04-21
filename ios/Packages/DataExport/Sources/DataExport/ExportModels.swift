import Foundation

// MARK: - ExportScope

public enum ExportScope: String, Codable, Sendable, CaseIterable {
    case fullTenant = "fullTenant"
    case domain = "domain"
    case customer = "customer"

    public var displayName: String {
        switch self {
        case .fullTenant: return "Full Tenant"
        case .domain:     return "Domain"
        case .customer:   return "Customer"
        }
    }
}

// MARK: - ExportStatus

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

// MARK: - ExportJob

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

// MARK: - ScheduledExport

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

// MARK: - ExportCadence

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

// MARK: - ExportDestination

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

// MARK: - API request / response helpers

public struct StartTenantExportRequest: Encodable, Sendable {
    public let passphrase: String
    public init(passphrase: String) { self.passphrase = passphrase }
}

public struct StartDomainExportRequest: Encodable, Sendable {
    public let filters: [String: String]
    public init(filters: [String: String]) { self.filters = filters }
}

public struct StartExportResponse: Decodable, Sendable {
    public let exportId: String
    public let status: String
}

public struct ExportStatusResponse: Decodable, Sendable {
    public let status: ExportStatus
    public let progressPct: Double
    public let downloadUrl: String?
    public let errorMessage: String?
}

public struct ExportError: Decodable, Sendable, Identifiable {
    public var id: String { message }
    public let message: String
    public let row: String?
}

public struct SaveScheduleRequest: Encodable, Sendable {
    public let cadence: String
    public let destination: String
    public init(cadence: ExportCadence, destination: ExportDestination) {
        self.cadence = cadence.rawValue
        self.destination = destination.rawValue
    }
}
