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

// MARK: - ImportEntityType

/// The CRM entity that will be populated by the import.
public enum ImportEntityType: String, Codable, Sendable, CaseIterable, Identifiable {
    case customers  = "customers"
    case inventory  = "inventory"
    case tickets    = "tickets"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .customers: return "Customers"
        case .inventory: return "Inventory"
        case .tickets:   return "Tickets"
        }
    }

    public var systemImage: String {
        switch self {
        case .customers: return "person.2"
        case .inventory: return "shippingbox"
        case .tickets:   return "wrench.adjustable"
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
    case paused     = "paused"     // §48.3 pause/resume
    case completed  = "completed"
    case failed     = "failed"
    case rolledBack = "rolled_back"

    /// Whether this job is actively processing (allows pause).
    public var isRunning: Bool { self == .running }

    /// Whether this job can be resumed.
    public var isPaused: Bool { self == .paused }
}

// MARK: - ImportJob

public struct ImportJob: Identifiable, Codable, Sendable {
    public let id: String
    public var source: ImportSource
    public var entityType: ImportEntityType
    public var fileId: String?
    public var status: ImportStatus
    public var totalRows: Int?
    public var processedRows: Int
    public var errorCount: Int
    public var createdAt: Date
    public var mapping: [String: String]
    /// Non-nil when a rollback is available (within 24 h of completion).
    public var rollbackAvailableUntil: Date?

    public init(
        id: String,
        source: ImportSource,
        entityType: ImportEntityType = .customers,
        fileId: String? = nil,
        status: ImportStatus = .draft,
        totalRows: Int? = nil,
        processedRows: Int = 0,
        errorCount: Int = 0,
        createdAt: Date = Date(),
        mapping: [String: String] = [:],
        rollbackAvailableUntil: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.entityType = entityType
        self.fileId = fileId
        self.status = status
        self.totalRows = totalRows
        self.processedRows = processedRows
        self.errorCount = errorCount
        self.createdAt = createdAt
        self.mapping = mapping
        self.rollbackAvailableUntil = rollbackAvailableUntil
    }

    public var canRollback: Bool {
        guard status == .completed, let until = rollbackAvailableUntil else { return false }
        return Date() < until
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, entityType, fileId, status, totalRows, processedRows, errorCount,
             createdAt, mapping, rollbackAvailableUntil
    }
}

// MARK: - ImportPreview

public struct ImportPreview: Codable, Sendable {
    public let columns: [String]
    public let rows: [[String]]
    public let totalRows: Int
    /// Rows where validation failed in the preview sample.
    public let flaggedRows: [ImportRowError]

    public init(
        columns: [String],
        rows: [[String]],
        totalRows: Int,
        flaggedRows: [ImportRowError] = []
    ) {
        self.columns = columns
        self.rows = rows
        self.totalRows = totalRows
        self.flaggedRows = flaggedRows
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

// MARK: - Chunked upload checkpoint

/// Persisted per-job upload progress. Allows resuming a chunked upload after
/// the app is foregrounded or the network recovers.
public struct ImportCheckpoint: Codable, Sendable {
    /// Import job ID on the server.
    public let jobId: String
    /// Total number of rows in the file.
    public let totalRows: Int
    /// Index of the next chunk to send (0-based).
    public var nextChunkIndex: Int
    /// Size of each chunk in rows.
    public let chunkSize: Int
    /// Timestamp of last successful chunk upload.
    public var lastUpdated: Date

    public init(
        jobId: String,
        totalRows: Int,
        nextChunkIndex: Int = 0,
        chunkSize: Int = 100,
        lastUpdated: Date = Date()
    ) {
        self.jobId = jobId
        self.totalRows = totalRows
        self.nextChunkIndex = nextChunkIndex
        self.chunkSize = chunkSize
        self.lastUpdated = lastUpdated
    }

    public var totalChunks: Int {
        max(1, Int(ceil(Double(totalRows) / Double(chunkSize))))
    }

    public var isComplete: Bool {
        nextChunkIndex >= totalChunks
    }

    public var progressFraction: Double {
        guard totalChunks > 0 else { return 0 }
        return min(1.0, Double(nextChunkIndex) / Double(totalChunks))
    }
}

// MARK: - Upload response

public struct FileUploadResponse: Codable, Sendable {
    public let fileId: String
}

// MARK: - Create job request / response

public struct CreateImportJobRequest: Codable, Sendable {
    public let source: String
    public let entityType: String
    public let fileId: String?
    public let mapping: [String: String]?

    public init(
        source: ImportSource,
        entityType: ImportEntityType,
        fileId: String? = nil,
        mapping: [String: String]? = nil
    ) {
        self.source = source.rawValue
        self.entityType = entityType.rawValue
        self.fileId = fileId
        self.mapping = mapping
    }
}

public struct CreateImportJobResponse: Codable, Sendable {
    public let importId: String
    public let status: String
}

// MARK: - Rollback request / response

public struct RollbackImportRequest: Encodable, Sendable {}

public struct RollbackImportResponse: Codable, Sendable {
    public let message: String
}

// MARK: - Internal request helpers (top-level to avoid Swift 6 generic nesting restriction)

struct ImportStartRequest: Encodable, Sendable {}
struct ImportMultipartBody: Encodable, Sendable {
    let filename: String
    let data: String // base64
}

// MARK: - §48.2 Error export response
public struct ImportErrorExportResponse: Codable, Sendable {
    public let url: String?
}

// MARK: - §48.3 Import errors
public enum ImportError: Error, Sendable {
    case noExportURL
    public var localizedDescription: String {
        switch self {
        case .noExportURL: return "Server did not return an export URL."
        }
    }
}

// MARK: - CRM field schema per entity type

/// All mappable CRM fields, keyed by entity type.
/// Adding a new entity: extend this enum and `CRMFieldRegistry`.
public enum CRMField: String, CaseIterable, Sendable {

    // MARK: Customer fields
    case firstName  = "customer.first_name"
    case lastName   = "customer.last_name"
    case phone      = "customer.phone"
    case email      = "customer.email"
    case address    = "customer.address"
    case city       = "customer.city"
    case state      = "customer.state"
    case zip        = "customer.zip"
    case notes      = "customer.notes"

    // MARK: Inventory fields
    case itemName   = "inventory.name"
    case itemSku    = "inventory.sku"
    case itemPrice  = "inventory.price"
    case itemCost   = "inventory.cost"
    case itemQty    = "inventory.quantity"
    case itemCategory = "inventory.category"
    case itemBarcode = "inventory.barcode"
    case itemDescription = "inventory.description"

    // MARK: Ticket fields
    case ticketDevice    = "ticket.device"
    case ticketProblem   = "ticket.problem"
    case ticketStatus    = "ticket.status"
    case ticketCustomerName = "ticket.customer_name"
    case ticketCustomerPhone = "ticket.customer_phone"
    case ticketCustomerEmail = "ticket.customer_email"
    case ticketCreatedAt = "ticket.created_at"
    case ticketNotes     = "ticket.notes"

    public var displayName: String {
        switch self {
        case .firstName:    return "First Name"
        case .lastName:     return "Last Name"
        case .phone:        return "Phone"
        case .email:        return "Email"
        case .address:      return "Address"
        case .city:         return "City"
        case .state:        return "State"
        case .zip:          return "ZIP Code"
        case .notes:        return "Notes"
        case .itemName:     return "Item Name"
        case .itemSku:      return "SKU"
        case .itemPrice:    return "Price"
        case .itemCost:     return "Cost"
        case .itemQty:      return "Quantity"
        case .itemCategory: return "Category"
        case .itemBarcode:  return "Barcode"
        case .itemDescription: return "Description"
        case .ticketDevice:       return "Device"
        case .ticketProblem:      return "Problem"
        case .ticketStatus:       return "Status"
        case .ticketCustomerName:  return "Customer Name"
        case .ticketCustomerPhone: return "Customer Phone"
        case .ticketCustomerEmail: return "Customer Email"
        case .ticketCreatedAt:    return "Created At"
        case .ticketNotes:        return "Notes"
        }
    }

    public var entityType: ImportEntityType {
        switch self {
        case .firstName, .lastName, .phone, .email, .address, .city, .state, .zip, .notes:
            return .customers
        case .itemName, .itemSku, .itemPrice, .itemCost, .itemQty, .itemCategory, .itemBarcode, .itemDescription:
            return .inventory
        case .ticketDevice, .ticketProblem, .ticketStatus, .ticketCustomerName,
             .ticketCustomerPhone, .ticketCustomerEmail, .ticketCreatedAt, .ticketNotes:
            return .tickets
        }
    }

    public var isRequired: Bool {
        switch self {
        case .firstName, .lastName, .phone, .email: return true
        case .itemName, .itemSku:                   return true
        case .ticketDevice, .ticketProblem:         return true
        default:                                    return false
        }
    }

    /// All fields for a given entity type.
    public static func fields(for entity: ImportEntityType) -> [CRMField] {
        allCases.filter { $0.entityType == entity }
    }

    /// Required fields for a given entity type.
    public static func requiredFields(for entity: ImportEntityType) -> [CRMField] {
        fields(for: entity).filter { $0.isRequired }
    }

    // Legacy helpers for callers that don't pass an entity type (default = customers).
    public static var requiredFields: [CRMField] { requiredFields(for: .customers) }
}
