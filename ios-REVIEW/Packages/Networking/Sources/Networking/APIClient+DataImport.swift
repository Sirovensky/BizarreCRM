import Foundation

/// Networking-layer extension for the Data Import wizard.
///
/// Routes confirmed against packages/server/src/routes/import.routes.ts
/// (mounted at /api/v1/import by index.ts).
///
/// The server uses source-specific paths rather than a generic /imports REST
/// resource:
///
///   POST /api/v1/import/repairdesk/test-connection
///   POST /api/v1/import/repairdesk/start
///   GET  /api/v1/import/repairdesk/status
///   POST /api/v1/import/repairdesk/cancel
///   POST /api/v1/import/repairshopr/test-connection
///   POST /api/v1/import/repairshopr/start
///   GET  /api/v1/import/repairshopr/status
///   POST /api/v1/import/repairshopr/cancel
///   POST /api/v1/import/myrepairapp/test-connection
///   POST /api/v1/import/myrepairapp/start
///   GET  /api/v1/import/myrepairapp/status
///   POST /api/v1/import/myrepairapp/cancel
///   GET  /api/v1/import/history
///
/// STUB NOTE: The server has no generic CSV-file-upload endpoint (no
/// /imports/upload, /imports/:id/preview, /imports/:id/start, etc.).
/// Those calls in the DataImport package's ImportEndpoints.swift are
/// stubs pending a server-side CSV pipeline feature. They will 404 until
/// the server implements them; see TODO below.
///
/// This file is append-only — add new import endpoints below, never change
/// existing signatures.
public extension APIClient {

    // MARK: - RepairDesk

    /// POST /import/repairdesk/test-connection
    /// Validates a RepairDesk API key without persisting it.
    func testRepairDeskConnection(apiKey: String) async throws -> ImportConnectionTestResponse {
        let body = ImportAPIKeyBody(apiKey: apiKey, entities: nil)
        return try await post("/import/repairdesk/test-connection", body: body, as: ImportConnectionTestResponse.self)
    }

    /// POST /import/repairdesk/start
    /// Kicks off a RepairDesk import for one or more entity types.
    /// - Parameters:
    ///   - apiKey: RepairDesk API key — never persisted server-side.
    ///   - entities: Non-empty array from ["customers","tickets","invoices","inventory","sms"].
    func startRepairDeskImport(apiKey: String, entities: [String]) async throws -> ImportStartResponse {
        let body = ImportAPIKeyBody(apiKey: apiKey, entities: entities)
        return try await post("/import/repairdesk/start", body: body, as: ImportStartResponse.self)
    }

    /// GET /import/repairdesk/status
    func repairDeskImportStatus() async throws -> ImportStatusResponse {
        return try await get("/import/repairdesk/status", as: ImportStatusResponse.self)
    }

    /// POST /import/repairdesk/cancel
    func cancelRepairDeskImport() async throws -> ImportCancelResponse {
        return try await post("/import/repairdesk/cancel", body: ImportEmptyBody(), as: ImportCancelResponse.self)
    }

    // MARK: - Shopr (RepairShopr)

    /// POST /import/repairshopr/test-connection
    func testShoprConnection(apiKey: String, subdomain: String) async throws -> ImportConnectionTestResponse {
        let body = ImportShoprBody(apiKey: apiKey, subdomain: subdomain, entities: nil)
        return try await post("/import/repairshopr/test-connection", body: body, as: ImportConnectionTestResponse.self)
    }

    /// POST /import/repairshopr/start
    func startShoprImport(apiKey: String, subdomain: String, entities: [String]) async throws -> ImportStartResponse {
        let body = ImportShoprBody(apiKey: apiKey, subdomain: subdomain, entities: entities)
        return try await post("/import/repairshopr/start", body: body, as: ImportStartResponse.self)
    }

    /// GET /import/repairshopr/status
    func shoprImportStatus() async throws -> ImportStatusResponse {
        return try await get("/import/repairshopr/status", as: ImportStatusResponse.self)
    }

    /// POST /import/repairshopr/cancel
    func cancelShoprImport() async throws -> ImportCancelResponse {
        return try await post("/import/repairshopr/cancel", body: ImportEmptyBody(), as: ImportCancelResponse.self)
    }

    // MARK: - MyRepairApp (MRA)

    /// POST /import/myrepairapp/test-connection
    func testMRAConnection(apiKey: String) async throws -> ImportConnectionTestResponse {
        let body = ImportAPIKeyBody(apiKey: apiKey, entities: nil)
        return try await post("/import/myrepairapp/test-connection", body: body, as: ImportConnectionTestResponse.self)
    }

    /// POST /import/myrepairapp/start
    func startMRAImport(apiKey: String, entities: [String]) async throws -> ImportStartResponse {
        let body = ImportAPIKeyBody(apiKey: apiKey, entities: entities)
        return try await post("/import/myrepairapp/start", body: body, as: ImportStartResponse.self)
    }

    /// GET /import/myrepairapp/status
    func mraImportStatus() async throws -> ImportStatusResponse {
        return try await get("/import/myrepairapp/status", as: ImportStatusResponse.self)
    }

    /// POST /import/myrepairapp/cancel
    func cancelMRAImport() async throws -> ImportCancelResponse {
        return try await post("/import/myrepairapp/cancel", body: ImportEmptyBody(), as: ImportCancelResponse.self)
    }

    // MARK: - History

    /// GET /import/history
    /// Returns paginated list of past import runs for all sources.
    func listImportHistory(page: Int = 1, pageSize: Int = 20) async throws -> ImportHistoryResponse {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pagesize", value: String(pageSize))
        ]
        return try await get("/import/history", query: query, as: ImportHistoryResponse.self)
    }

    // MARK: - CSV (STUB — server endpoints not yet implemented)
    //
    // TODO: The server has no CSV-upload pipeline yet. These methods encode
    // file data as base64 JSON and will 404 until the server implements:
    //   POST /import/csv/upload    — receive multipart/form-data, return { fileId }
    //   GET  /import/csv/:id/preview  — return first 10 rows + columns
    //   POST /import/csv/:id/start — begin CSV row processing
    //   GET  /import/csv/:id/status — poll run status
    //
    // Until then, callers in the DataImport wizard will receive a network
    // error that surfaces as vm.errorMessage in ImportWizardViewModel.
}

// MARK: - Request bodies

/// Generic API key + entities body (RepairDesk, MRA).
struct ImportAPIKeyBody: Encodable, Sendable {
    let apiKey: String
    let entities: [String]?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case entities
    }
}

/// Shopr-specific body that also requires a subdomain.
struct ImportShoprBody: Encodable, Sendable {
    let apiKey: String
    let subdomain: String
    let entities: [String]?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case subdomain
        case entities
    }
}

/// Empty POST body for cancel endpoints.
struct ImportEmptyBody: Encodable, Sendable {}

// MARK: - Response shapes
// Decoded from server { success: bool, data: T } envelope by APIClientImpl.

/// Response from test-connection endpoints.
public struct ImportConnectionTestResponse: Decodable, Sendable {
    public let ok: Bool
    public let message: String?

    public init(ok: Bool, message: String?) {
        self.ok = ok
        self.message = message
    }
}

/// Response from /start endpoints — mirrors the server's run array shape.
public struct ImportStartResponse: Decodable, Sendable {
    public let runs: [ImportRun]
    public let isActive: Bool

    public init(runs: [ImportRun], isActive: Bool) {
        self.runs = runs
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case runs
        case isActive = "is_active"
    }
}

/// Response from /status endpoints.
public struct ImportStatusResponse: Decodable, Sendable {
    public let isActive: Bool
    public let overall: ImportOverall?
    public let runs: [ImportRun]

    public init(isActive: Bool, overall: ImportOverall?, runs: [ImportRun]) {
        self.isActive = isActive
        self.overall = overall
        self.runs = runs
    }

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case overall
        case runs
    }
}

/// Aggregated progress across all entity runs in a batch.
public struct ImportOverall: Decodable, Sendable {
    public let totalEntities: Int
    public let completedEntities: Int
    public let totalRecords: Int
    public let imported: Int
    public let skipped: Int
    public let errors: Int

    public init(totalEntities: Int, completedEntities: Int, totalRecords: Int, imported: Int, skipped: Int, errors: Int) {
        self.totalEntities = totalEntities
        self.completedEntities = completedEntities
        self.totalRecords = totalRecords
        self.imported = imported
        self.skipped = skipped
        self.errors = errors
    }

    enum CodingKeys: String, CodingKey {
        case totalEntities = "total_entities"
        case completedEntities = "completed_entities"
        case totalRecords = "total_records"
        case imported
        case skipped
        case errors
    }
}

/// A single import_runs row from the server.
public struct ImportRun: Decodable, Identifiable, Sendable {
    public let id: Int
    public let source: String
    public let entityType: String
    public let status: String
    public let imported: Int?
    public let skipped: Int?
    public let errors: Int?
    public let totalRecords: Int?
    public let startedAt: String?
    public let completedAt: String?

    public init(
        id: Int, source: String, entityType: String, status: String,
        imported: Int?, skipped: Int?, errors: Int?, totalRecords: Int?,
        startedAt: String?, completedAt: String?
    ) {
        self.id = id
        self.source = source
        self.entityType = entityType
        self.status = status
        self.imported = imported
        self.skipped = skipped
        self.errors = errors
        self.totalRecords = totalRecords
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, source, status, imported, skipped, errors
        case entityType = "entity_type"
        case totalRecords = "total_records"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

/// Response from GET /import/history.
public struct ImportHistoryResponse: Decodable, Sendable {
    public let runs: [ImportRun]
    public let pagination: ImportPagination

    public init(runs: [ImportRun], pagination: ImportPagination) {
        self.runs = runs
        self.pagination = pagination
    }
}

public struct ImportPagination: Decodable, Sendable {
    public let page: Int
    public let perPage: Int
    public let total: Int
    public let totalPages: Int

    public init(page: Int, perPage: Int, total: Int, totalPages: Int) {
        self.page = page
        self.perPage = perPage
        self.total = total
        self.totalPages = totalPages
    }

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case total
        case totalPages = "total_pages"
    }
}

/// Response from cancel endpoints.
public struct ImportCancelResponse: Decodable, Sendable {
    public let cancelled: Bool
    public let message: String?

    public init(cancelled: Bool, message: String?) {
        self.cancelled = cancelled
        self.message = message
    }
}
