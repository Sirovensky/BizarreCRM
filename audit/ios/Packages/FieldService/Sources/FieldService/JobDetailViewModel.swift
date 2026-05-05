// §57.2 JobDetailViewModel — drives job detail + tech status update screen.
//
// Loads GET /field-service/jobs/:id, then provides status-transition action
// via POST /field-service/jobs/:id/status.
//
// Location-based check-in (status → on_site) uses injected LocationCapture;
// if permission is denied, falls back to manual status update without coords.
// Platform-agnostic: no SwiftUI imports.

import Foundation
import Observation
import CoreLocation
import Networking

// MARK: - JobDetailViewModel

@MainActor
@Observable
public final class JobDetailViewModel {

    // MARK: - State

    public enum ViewState: Sendable, Equatable {
        case loading
        case loaded(FSJob)
        case updating
        case updated(FSJob, newStatus: FSJobStatus)
        case failed(String)
    }

    public private(set) var state: ViewState = .loading

    /// Non-fatal user-facing alert message (e.g. location denied fallback notice).
    public private(set) var alertMessage: String? = nil

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let locationCapture: LocationCapture?

    private let jobId: Int64

    // MARK: - Init

    public init(jobId: Int64, api: APIClient, locationCapture: LocationCapture? = nil) {
        self.jobId = jobId
        self.api = api
        self.locationCapture = locationCapture
    }

    // MARK: - Public API

    public func load() async {
        state = .loading
        do {
            let job = try await api.fieldServiceJob(id: jobId)
            state = .loaded(job)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Transition the job to `newStatus`.
    ///
    /// For `onSite`, attempts to capture GPS coords.
    /// If location permission is denied, transitions status without coords
    /// (manual fallback) and shows an alert message.
    public func updateStatus(to newStatus: FSJobStatus, notes: String? = nil) async {
        guard case .loaded(let job) = state else { return }
        state = .updating

        // Attempt location capture for on_site transitions.
        var lat: Double? = nil
        var lng: Double? = nil

        if newStatus == .onSite, let capture = locationCapture {
            do {
                let location = try await capture.captureCurrentLocation()
                lat = location.coordinate.latitude
                lng = location.coordinate.longitude
            } catch FieldCheckInError.locationPermissionDenied {
                alertMessage = "Location access denied. Status updated without GPS coordinates."
                // Continue with manual update (no coords).
            } catch {
                alertMessage = "Could not determine location. Status updated without GPS coordinates."
            }
        }

        let request = FSJobStatusRequest(
            status: newStatus,
            locationLat: lat,
            locationLng: lng,
            notes: notes
        )

        do {
            _ = try await api.updateFieldServiceJobStatus(id: jobId, request: request)
            // Rebuild job with updated status (server returns only {id, status}).
            let updatedJob = FSJob(
                id: job.id,
                ticketId: job.ticketId,
                customerId: job.customerId,
                addressLine: job.addressLine,
                city: job.city,
                state: job.state,
                postcode: job.postcode,
                lat: job.lat,
                lng: job.lng,
                scheduledWindowStart: job.scheduledWindowStart,
                scheduledWindowEnd: job.scheduledWindowEnd,
                priority: job.priority,
                status: newStatus.rawValue,
                estimatedDurationMinutes: job.estimatedDurationMinutes,
                actualDurationMinutes: job.actualDurationMinutes,
                notes: job.notes,
                technicianNotes: job.technicianNotes,
                assignedTechnicianId: job.assignedTechnicianId,
                customerFirstName: job.customerFirstName,
                customerLastName: job.customerLastName,
                techFirstName: job.techFirstName,
                techLastName: job.techLastName,
                createdAt: job.createdAt,
                updatedAt: nil
            )
            state = .updated(updatedJob, newStatus: newStatus)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func dismissAlert() {
        alertMessage = nil
    }

    public func retry() async {
        await load()
    }
}

// MARK: - FSJob memberwise init (needed by JobDetailViewModel to rebuild)

extension FSJob {
    // swiftlint:disable:next function_parameter_count
    init(
        id: Int64,
        ticketId: Int64?,
        customerId: Int64?,
        addressLine: String,
        city: String?,
        state: String?,
        postcode: String?,
        lat: Double,
        lng: Double,
        scheduledWindowStart: String?,
        scheduledWindowEnd: String?,
        priority: String,
        status: String,
        estimatedDurationMinutes: Int?,
        actualDurationMinutes: Int?,
        notes: String?,
        technicianNotes: String?,
        assignedTechnicianId: Int64?,
        customerFirstName: String?,
        customerLastName: String?,
        techFirstName: String?,
        techLastName: String?,
        createdAt: String?,
        updatedAt: String?
    ) {
        self.id = id
        self.ticketId = ticketId
        self.customerId = customerId
        self.addressLine = addressLine
        self.city = city
        self.state = state
        self.postcode = postcode
        self.lat = lat
        self.lng = lng
        self.scheduledWindowStart = scheduledWindowStart
        self.scheduledWindowEnd = scheduledWindowEnd
        self.priority = priority
        self.status = status
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.actualDurationMinutes = actualDurationMinutes
        self.notes = notes
        self.technicianNotes = technicianNotes
        self.assignedTechnicianId = assignedTechnicianId
        self.customerFirstName = customerFirstName
        self.customerLastName = customerLastName
        self.techFirstName = techFirstName
        self.techLastName = techLastName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
