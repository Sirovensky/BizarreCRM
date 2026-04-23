import Foundation
import Networking

// MARK: - Import API endpoints

extension APIClient {

    /// POST /imports/upload — multipart form upload. Returns fileId.
    public func uploadImportFile(data: Data, filename: String) async throws -> FileUploadResponse {
        // Build multipart body manually
        let boundary = "BizarreCRM-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Use postMultipart which posts raw Data with Content-Type header
        return try await postMultipart("/imports/upload", body: body, boundary: boundary, as: FileUploadResponse.self)
    }

    /// POST /imports — create import job
    /// - Parameters:
    ///   - source: Import source system (csv, repairDesk, etc.)
    ///   - entityType: Target entity (customers, inventory, tickets)
    ///   - fileId: Server file ID from the upload step
    ///   - mapping: Column→field mapping dict (optional at create time, required before start)
    public func createImportJob(
        source: ImportSource,
        entityType: ImportEntityType,
        fileId: String?,
        mapping: [String: String]?
    ) async throws -> CreateImportJobResponse {
        let req = CreateImportJobRequest(source: source, entityType: entityType, fileId: fileId, mapping: mapping)
        return try await post("/imports", body: req, as: CreateImportJobResponse.self)
    }

    /// POST /imports/:id/rollback — roll back a completed import (within 24 h window).
    /// Server endpoint: POST /api/v1/import/:id/rollback
    /// NOTE: This endpoint is not yet present in import.routes.ts — tracked as missing endpoint.
    public func rollbackImport(id: String) async throws -> RollbackImportResponse {
        return try await post("/imports/\(id)/rollback", body: RollbackImportRequest(), as: RollbackImportResponse.self)
    }

    /// GET /imports/:id — poll status
    public func getImportJob(id: String) async throws -> ImportJob {
        return try await get("/imports/\(id)", as: ImportJob.self)
    }

    /// GET /imports/:id/preview — first 10 rows + detected columns
    public func getImportPreview(id: String) async throws -> ImportPreview {
        return try await get("/imports/\(id)/preview", as: ImportPreview.self)
    }

    /// POST /imports/:id/start — begin processing
    public func startImport(id: String) async throws -> ImportJob {
        return try await post("/imports/\(id)/start", body: ImportStartRequest(), as: ImportJob.self)
    }

    /// GET /imports/:id/errors — row-level errors
    public func getImportErrors(id: String) async throws -> [ImportRowError] {
        return try await get("/imports/\(id)/errors", as: [ImportRowError].self)
    }

    /// GET /imports — import history list
    public func listImportJobs() async throws -> [ImportJob] {
        return try await get("/imports", as: [ImportJob].self)
    }

    // MARK: - Internal multipart helper

    private func postMultipart<T: Decodable & Sendable>(
        _ path: String,
        body: Data,
        boundary: String,
        as type: T.Type
    ) async throws -> T {
        // Since APIClient protocol only exposes typed post, we encode the file
        // as base64 in a JSON body for stub compatibility.
        let wrapper = ImportMultipartBody(filename: "file", data: body.base64EncodedString())
        return try await post(path, body: wrapper, as: T.self)
    }
}
