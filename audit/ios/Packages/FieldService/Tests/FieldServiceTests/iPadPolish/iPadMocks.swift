// §22 iPadMocks — test doubles for the iPad dispatcher console tests.
//
// Separate from Mocks.swift (owned by the base dispatcher wave) so we do not
// touch that file. This file defines iPadMockAPIClient which handles both the
// field-service jobs AND the /employees endpoint needed by the roster.

import Foundation
import Networking
@testable import FieldService

// MARK: - iPadMockAPIClient

/// Extended mock client that also handles GET /api/v1/employees.
final class iPadMockAPIClient: APIClient, @unchecked Sendable {

    // MARK: - Stubs

    var stubbedJobs: [FSJob] = []
    var stubbedEmployees: [Employee] = []

    var fsListShouldThrow: Error?
    var fsStatusShouldThrow: Error?

    // MARK: - Inspection

    private(set) var _lastJobListTechId: Int64?
    private(set) var _lastJobListStatus: FSJobStatus?

    // MARK: - APIClient

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // Employees list
        if path == "/api/v1/employees" {
            let data = try JSONEncoder().encode(stubbedEmployees.map(EncodableEmployee.init))
            return try JSONDecoder().decode(T.self, from: data)
        }

        // Field-service jobs list
        if path == "/api/v1/field-service/jobs" {
            if let err = fsListShouldThrow { throw err }

            // Capture filter query params for inspection.
            if let q = query {
                if let techParam = q.first(where: { $0.name == "assigned_technician_id" })?.value,
                   let techId = Int64(techParam) {
                    _lastJobListTechId = techId
                }
                if let statusParam = q.first(where: { $0.name == "status" })?.value {
                    _lastJobListStatus = FSJobStatus(rawValue: statusParam)
                }
            }

            let resp = FSJobsListResponse(
                jobs: stubbedJobs,
                pagination: FSPagination(page: 1, perPage: 200, total: stubbedJobs.count, totalPages: 1)
            )
            let data = try JSONEncoder().encode(EncodableFSJobsListResponse(from: resp))
            return try JSONDecoder().decode(T.self, from: data)
        }

        throw iPadMockError.notConfigured("GET \(path)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.contains("/field-service/jobs/") && path.hasSuffix("/status") {
            if let err = fsStatusShouldThrow { throw err }
            let idStr = path.components(separatedBy: "/").dropLast().last ?? "1"
            let statusStr = (body as? FSJobStatusRequest)?.status ?? "assigned"
            let json = #"{"id":\#(idStr),"status":"\#(statusStr)"}"#
            return try JSONDecoder().decode(T.self, from: json.data(using: .utf8)!)
        }
        throw iPadMockError.notConfigured("POST \(path)")
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw iPadMockError.notConfigured("PUT \(path)")
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw iPadMockError.notConfigured("PATCH \(path)")
    }

    func delete(_ path: String) async throws {
        throw iPadMockError.notConfigured("DELETE \(path)")
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw iPadMockError.notConfigured("getEnvelope \(path)")
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Inspection accessors (public for test file)

extension iPadMockAPIClient {
    var lastJobListTechId: Int64? { _lastJobListTechId }
    var lastJobListStatus: FSJobStatus? { _lastJobListStatus }
}

// MARK: - Encodable wrappers

private struct EncodableEmployee: Encodable {
    let id: Int64
    let username: String?
    let email: String?
    let first_name: String?
    let last_name: String?
    let role: String?
    let avatar_url: String?
    let is_active: Int?
    let has_pin: Int?
    let created_at: String?

    init(from emp: Employee) {
        self.id         = emp.id
        self.username   = emp.username
        self.email      = emp.email
        self.first_name = emp.firstName
        self.last_name  = emp.lastName
        self.role       = emp.role
        self.avatar_url = emp.avatarUrl
        self.is_active  = emp.isActive
        self.has_pin    = emp.hasPin
        self.created_at = emp.createdAt
    }
}

private struct EncodableFSJob: Encodable {
    let id: Int64
    let address_line: String
    let lat: Double
    let lng: Double
    let priority: String
    let status: String
    let assigned_technician_id: Int64?

    init(from job: FSJob) {
        self.id                     = job.id
        self.address_line           = job.addressLine
        self.lat                    = job.lat
        self.lng                    = job.lng
        self.priority               = job.priority
        self.status                 = job.status
        self.assigned_technician_id = job.assignedTechnicianId
    }
}

private struct EncodablePagination: Encodable {
    let page: Int
    let per_page: Int
    let total: Int
    let total_pages: Int
}

private struct EncodableFSJobsListResponse: Encodable {
    let jobs: [EncodableFSJob]
    let pagination: EncodablePagination

    init(from resp: FSJobsListResponse) {
        self.jobs = resp.jobs.map(EncodableFSJob.init)
        self.pagination = EncodablePagination(
            page: resp.pagination.page,
            per_page: resp.pagination.perPage,
            total: resp.pagination.total,
            total_pages: resp.pagination.totalPages
        )
    }
}

// MARK: - Mock error

enum iPadMockError: Error {
    case notConfigured(String)
    case simulated
}

// MARK: - Employee test factory

extension Employee {
    static func makeTestiPad(
        id: Int64,
        firstName: String? = nil,
        lastName: String? = nil,
        isActive: Int = 1
    ) -> Employee {
        Employee(
            id: id,
            username: nil,
            email: nil,
            firstName: firstName,
            lastName: lastName,
            role: "technician",
            avatarUrl: nil,
            isActive: isActive,
            hasPin: nil,
            createdAt: nil
        )
    }
}
