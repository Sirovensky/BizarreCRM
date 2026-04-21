import Foundation

// MARK: - ImportSource

public enum ImportSource: String, Codable, Sendable, CaseIterable {
    case repairDesk = "repairDesk"
    case shopr = "shopr"
    case mra = "mra"
    case csv = "csv"

    public var displayName: String {
        switch self {
        case .repairDesk: return "RepairDesk"
        case .shopr:      return "Shopr"
        case .mra:        return "MRA"
        case .csv:        return "CSV / Excel"
        }
    }

    public var systemImage: String {
        switch self {
        case .repairDesk: return "wrench.and.screwdriver"
        case .shopr:      return "cart"
        case .mra:        return "building.2"
        case .csv:        return "tablecells"
        }
    }
}

// MARK: - ImportStatus

public enum ImportStatus: String, Codable, Sendable {
    case draft      = "draft"
    case uploading  = "uploading"
    case previewing = "previewing"
    case mapping    = "mapping"
    case running    = "running"
    case completed  = "completed"
    case failed     = "failed"
}

// MARK: - ImportJob

public struct ImportJob: Identifiable, Codable, Sendable {
    public let id: String
    public var source: ImportSource
    public var fileId: String?
    public var status: ImportStatus
    public var totalRows: Int?
    public var processedRows: Int
    public var errorCount: Int
    public var createdAt: Date
    public var mapping: [String: String]

    public init(
        id: String,
        source: ImportSource,
        fileId: String? = nil,
        status: ImportStatus = .draft,
        totalRows: Int? = nil,
        processedRows: Int = 0,
        errorCount: Int = 0,
        createdAt: Date = Date(),
        mapping: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.fileId = fileId
        self.status = status
        self.totalRows = totalRows
        self.processedRows = processedRows
        self.errorCount = errorCount
        self.createdAt = createdAt
        self.mapping = mapping
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, fileId, status, totalRows, processedRows, errorCount, createdAt, mapping
    }
}

// MARK: - ImportPreview

public struct ImportPreview: Codable, Sendable {
    public let columns: [String]
    public let rows: [[String]]
    public let totalRows: Int

    public init(columns: [String], rows: [[String]], totalRows: Int) {
        self.columns = columns
        self.rows = rows
        self.totalRows = totalRows
    }
}

// MARK: - ImportRowError

public struct ImportRowError: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(row)-\(column ?? "")" }
    public let row: Int
    public let column: String?
    public let reason: String

    public init(row: Int, column: String?, reason: String) {
        self.row = row
        self.column = column
        self.reason = reason
    }
}

// MARK: - Upload response

public struct FileUploadResponse: Codable, Sendable {
    public let fileId: String
}

// MARK: - Create job request / response

public struct CreateImportJobRequest: Codable, Sendable {
    public let source: String
    public let fileId: String?
    public let mapping: [String: String]?

    public init(source: ImportSource, fileId: String? = nil, mapping: [String: String]? = nil) {
        self.source = source.rawValue
        self.fileId = fileId
        self.mapping = mapping
    }
}

public struct CreateImportJobResponse: Codable, Sendable {
    public let importId: String
    public let status: String
}

// MARK: - Internal request helpers (top-level to avoid Swift 6 generic nesting restriction)

struct ImportStartRequest: Encodable, Sendable {}
struct ImportMultipartBody: Encodable, Sendable {
    let filename: String
    let data: String // base64
}

// MARK: - Required CRM target fields

public enum CRMField: String, CaseIterable, Sendable {
    // Required
    case firstName  = "customer.first_name"
    case lastName   = "customer.last_name"
    case phone      = "customer.phone"
    case email      = "customer.email"
    // Optional
    case address    = "customer.address"
    case city       = "customer.city"
    case state      = "customer.state"
    case zip        = "customer.zip"
    case notes      = "customer.notes"

    public var displayName: String {
        switch self {
        case .firstName: return "First Name"
        case .lastName:  return "Last Name"
        case .phone:     return "Phone"
        case .email:     return "Email"
        case .address:   return "Address"
        case .city:      return "City"
        case .state:     return "State"
        case .zip:       return "ZIP Code"
        case .notes:     return "Notes"
        }
    }

    public var isRequired: Bool {
        switch self {
        case .firstName, .lastName, .phone, .email: return true
        default: return false
        }
    }

    public static var requiredFields: [CRMField] {
        allCases.filter { $0.isRequired }
    }
}
