// Test mocks for FieldService package tests.

import Foundation
import CoreLocation
import Networking
import Core
@testable import FieldService

// MARK: - MockAPIClient

final class MockAPIClient: APIClient, @unchecked Sendable {

    // MARK: - Configurable stubs

    var postShouldThrow: Error?
    var getShouldThrow: Error?

    // MARK: - FieldService-specific stubs

    /// Jobs returned by listFieldServiceJobs / fieldServiceJob.
    var stubbedJobs: [FSJob] = []
    /// If set, overrides stubbedJobs response with an error.
    var fsListShouldThrow: Error?
    var fsDetailShouldThrow: Error?
    var fsStatusShouldThrow: Error?

    /// Last status request received by updateFieldServiceJobStatus.
    var lastStatusRequest: FSJobStatusRequest?
    var lastStatusJobId: Int64?

    // MARK: - APIClient conformance

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // Field-service jobs list
        if path.hasPrefix("/api/v1/field-service/jobs") && !path.contains("/status") {
            if let err = fsDetailShouldThrow ?? fsListShouldThrow { throw err }
            if let err = getShouldThrow { throw err }
            if path == "/api/v1/field-service/jobs" {
                // Return as FSJobsListResponse
                if T.self == FSJobsListResponse.self {
                    let resp = FSJobsListResponse(
                        jobs: stubbedJobs,
                        pagination: FSPagination(page: 1, perPage: 25, total: stubbedJobs.count, totalPages: 1)
                    )
                    // Encode/decode roundtrip to satisfy generic type system.
                    let data = try JSONEncoder().encode(EncodedFSJobsListResponse(from: resp))
                    return try JSONDecoder().decode(T.self, from: data)
                }
            } else {
                // /api/v1/field-service/jobs/:id
                if T.self == FSJob.self {
                    let idStr = path.components(separatedBy: "/").last ?? ""
                    if let id = Int64(idStr), let job = stubbedJobs.first(where: { $0.id == id }) {
                        let data = try JSONEncoder().encode(EncodedFSJob(from: job))
                        return try JSONDecoder().decode(T.self, from: data)
                    }
                    throw APITransportError.httpStatus(404, message: "Job not found")
                }
            }
        }

        if let err = getShouldThrow { throw err }
        throw MockError.notConfigured("GET \(path)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Field-service status update
        if path.contains("/field-service/jobs/") && path.hasSuffix("/status") {
            if let err = fsStatusShouldThrow { throw err }
            if let req = body as? FSJobStatusRequest {
                lastStatusRequest = req
                lastStatusJobId = Int64(path.components(separatedBy: "/").dropLast().last ?? "0")
            }
            // Return { id: 1, status: "..." }
            let idStr = path.components(separatedBy: "/").dropLast().last ?? "1"
            let statusStr = (body as? FSJobStatusRequest)?.status ?? "on_site"
            let json = #"{"id":\#(idStr),"status":"\#(statusStr)"}"#
            let data = json.data(using: .utf8)!
            return try JSONDecoder().decode(T.self, from: data)
        }

        if let err = postShouldThrow { throw err }
        // Return a bare Decodable from empty JSON `{}`.
        let data = "{}".data(using: .utf8)!
        return try JSONDecoder().decode(T.self, from: data)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw MockError.notConfigured("PUT \(path)")
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw MockError.notConfigured("PATCH \(path)")
    }

    func delete(_ path: String) async throws {
        throw MockError.notConfigured("DELETE \(path)")
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw MockError.notConfigured("getEnvelope \(path)")
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Encode helpers (for MockAPIClient get<FSJob/FSJobsListResponse>)

// These encode FSJob/FSJobsListResponse into JSON so the mock can decode
// them back as generic T — avoids the Swift type-erasure limitation.

private struct EncodedFSJob: Encodable {
    let id: Int64
    let addressLine: String
    let lat: Double
    let lng: Double
    let priority: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case addressLine  = "address_line"
        case lat, lng, priority, status
    }

    init(from job: FSJob) {
        self.id = job.id
        self.addressLine = job.addressLine
        self.lat = job.lat
        self.lng = job.lng
        self.priority = job.priority
        self.status = job.status
    }
}

private struct EncodedFSJobsListResponse: Encodable {
    let jobs: [EncodedFSJob]
    let pagination: EncodedPagination

    struct EncodedPagination: Encodable {
        let page: Int
        let per_page: Int
        let total: Int
        let total_pages: Int
    }

    init(from response: FSJobsListResponse) {
        self.jobs = response.jobs.map { EncodedFSJob(from: $0) }
        self.pagination = EncodedPagination(
            page: response.pagination.page,
            per_page: response.pagination.perPage,
            total: response.pagination.total,
            total_pages: response.pagination.totalPages
        )
    }
}

// MARK: - MockLocationCapture

final class MockLocationCapture: LocationCapture, @unchecked Sendable {
    var stubbedLocation: CLLocation?
    var stubbedError: Error?

    func captureCurrentLocation() async throws -> CLLocation {
        if let err = stubbedError { throw err }
        if let loc = stubbedLocation { return loc }
        throw FieldCheckInError.locationTimeout
    }
}

// MARK: - MockCLLocationManager

final class MockCLLocationManager: CLLocationManagerProtocol, @unchecked Sendable {

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var requestedWhenInUse = false
    private(set) var requestedAlways = false
    private(set) var startedUpdating = false
    private(set) var stoppedUpdating = false
    private(set) var startedSignificant = false
    private(set) var stoppedSignificant = false

    func requestWhenInUseAuthorization() { requestedWhenInUse = true }
    func requestAlwaysAuthorization() { requestedAlways = true }
    func startUpdatingLocation() { startedUpdating = true }
    func stopUpdatingLocation() { stoppedUpdating = true }
    func startMonitoringSignificantLocationChanges() { startedSignificant = true }
    func stopMonitoringSignificantLocationChanges() { stoppedSignificant = true }
}

// MARK: - MockCheckInService

actor MockCheckInService: FieldCheckInServiceProtocol {
    // nonisolated(unsafe) lets tests set these from @MainActor context.
    nonisolated(unsafe) var checkInShouldThrow: Error?
    nonisolated(unsafe) var checkOutShouldThrow: Error?
    private(set) var checkInCallCount = 0

    func checkIn(appointmentId: Int64, customerAddress: String) async throws {
        checkInCallCount += 1
        if let err = checkInShouldThrow { throw err }
    }

    func checkOut(appointmentId: Int64, signature: Data) async throws {
        if let err = checkOutShouldThrow { throw err }
    }
}

// MARK: - MockError

enum MockError: Error {
    case notConfigured(String)
    case simulated
}

// MARK: - FSJob test factory

extension FSJob {
    static func makeTest(
        id: Int64 = 1,
        status: FSJobStatus = .assigned,
        priority: String = "normal",
        customerFirstName: String? = "Alice",
        customerLastName: String? = "Smith",
        addressLine: String = "123 Main St",
        lat: Double = 37.33,
        lng: Double = -122.02
    ) -> FSJob {
        FSJob(
            id: id,
            ticketId: nil,
            customerId: 42,
            addressLine: addressLine,
            city: "Cupertino",
            state: "CA",
            postcode: "95014",
            lat: lat,
            lng: lng,
            scheduledWindowStart: "2026-04-23 09:00:00",
            scheduledWindowEnd: "2026-04-23 11:00:00",
            priority: priority,
            status: status.rawValue,
            estimatedDurationMinutes: 60,
            actualDurationMinutes: nil,
            notes: nil,
            technicianNotes: nil,
            assignedTechnicianId: 5,
            customerFirstName: customerFirstName,
            customerLastName: customerLastName,
            techFirstName: "Bob",
            techLastName: "Tech",
            createdAt: "2026-04-22 08:00:00",
            updatedAt: "2026-04-22 08:00:00"
        )
    }
}
