import Foundation
import Networking
import Core

// MARK: - Protocol

public protocol ImportRepository: Sendable {
    func uploadFile(data: Data, filename: String) async throws -> FileUploadResponse
    func createJob(source: ImportSource, entityType: ImportEntityType, fileId: String?, mapping: [String: String]?) async throws -> CreateImportJobResponse
    func getJob(id: String) async throws -> ImportJob
    func getPreview(id: String) async throws -> ImportPreview
    func startJob(id: String) async throws -> ImportJob
    func getErrors(id: String) async throws -> [ImportRowError]
    func listJobs() async throws -> [ImportJob]
    func rollbackJob(id: String) async throws -> RollbackImportResponse
}

// MARK: - Live implementation

public final class LiveImportRepository: ImportRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func uploadFile(data: Data, filename: String) async throws -> FileUploadResponse {
        try await api.uploadImportFile(data: data, filename: filename)
    }

    public func createJob(
        source: ImportSource,
        entityType: ImportEntityType,
        fileId: String?,
        mapping: [String: String]?
    ) async throws -> CreateImportJobResponse {
        try await api.createImportJob(source: source, entityType: entityType, fileId: fileId, mapping: mapping)
    }

    public func getJob(id: String) async throws -> ImportJob {
        try await api.getImportJob(id: id)
    }

    public func getPreview(id: String) async throws -> ImportPreview {
        try await api.getImportPreview(id: id)
    }

    public func startJob(id: String) async throws -> ImportJob {
        try await api.startImport(id: id)
    }

    public func getErrors(id: String) async throws -> [ImportRowError] {
        try await api.getImportErrors(id: id)
    }

    public func listJobs() async throws -> [ImportJob] {
        try await api.listImportJobs()
    }

    public func rollbackJob(id: String) async throws -> RollbackImportResponse {
        try await api.rollbackImport(id: id)
    }
}
