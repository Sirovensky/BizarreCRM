// §57.2 FieldCheckInPromptViewModel — drives the auto-check-in prompt
// shown when the technician enters the customer geofence.
//
// Designed to be platform-agnostic (no SwiftUI imports) for unit testing.

import Foundation
import Observation
import Networking
import Core

// MARK: - FieldCheckInPromptViewModel

@MainActor
@Observable
public final class FieldCheckInPromptViewModel {

    // MARK: - State

    public enum PromptState: Sendable, Equatable, CustomStringConvertible {
        public var description: String {
            switch self {
            case .idle: return "idle"
            case .prompting: return "prompting"
            case .checkingIn: return "checkingIn"
            case .checkedIn: return "checkedIn"
            case .failed(let m): return "failed(\(m))"
            }
        }
        case idle
        case prompting(appointmentId: Int64, customerName: String, address: String)
        case checkingIn
        case checkedIn
        case failed(String)
    }

    public private(set) var state: PromptState = .idle

    // MARK: - Dependencies

    @ObservationIgnored private let checkInService: any FieldCheckInServiceProtocol

    // MARK: - Init

    public init(checkInService: any FieldCheckInServiceProtocol) {
        self.checkInService = checkInService
    }

    // MARK: - Public API

    /// Called by the geofence monitor when the technician enters the region
    /// for `appointmentId`. Transitions to `.prompting`.
    public func geofenceEntered(
        appointmentId: Int64,
        customerName: String,
        address: String
    ) {
        guard case .idle = state else { return }
        state = .prompting(
            appointmentId: appointmentId,
            customerName: customerName,
            address: address
        )
    }

    /// User taps "Check In" on the prompt sheet.
    public func confirmCheckIn(appointmentId: Int64, address: String) async {
        state = .checkingIn
        do {
            try await checkInService.checkIn(
                appointmentId: appointmentId,
                customerAddress: address
            )
            state = .checkedIn
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// User dismisses the prompt without checking in.
    public func dismiss() {
        state = .idle
    }

    /// Reset after error — allows retry.
    public func retryReset() {
        state = .idle
    }
}
