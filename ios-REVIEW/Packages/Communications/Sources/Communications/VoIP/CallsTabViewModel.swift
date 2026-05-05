import Foundation
import Observation
import Networking
import Core

// MARK: - §12.10 Calls Tab ViewModel

/// ViewModel for the §12.10 Calls tab.
/// Manages inbound / outbound / missed call log, initiating calls, hangup, and transcription display.
@MainActor
@Observable
public final class CallsTabViewModel {

    // MARK: - Published state

    /// Full call log from the server.
    public var calls: [CallLogEntry] = []

    /// Whether the initial load is in progress.
    public var isLoading: Bool = false

    /// Non-fatal banner message (e.g., "Calls not available — VoIP not enabled for this account").
    public var infoMessage: String? = nil

    /// Fatal error message (network failure, unexpected 5xx).
    public var errorMessage: String? = nil

    /// The call currently being initiated or connected (nil = no active outbound call).
    public var activeOutboundCallId: Int64? = nil

    /// Whether a hangup is in progress.
    public var isHangingUp: Bool = false

    /// The call detail whose recording is being played (drives `CallRecordingPlayer` sheet).
    public var selectedForPlayback: CallLogEntry? = nil

    /// The call whose transcription is being shown.
    public var selectedForTranscript: CallLogEntry? = nil

    // MARK: - Dependencies

    private let repo: any CallLogRepository

    // MARK: - Init

    public init(repo: any CallLogRepository) {
        self.repo = repo
    }

    // MARK: - Load

    /// Initial load + pull-to-refresh.
    public func load() async {
        isLoading = calls.isEmpty
        errorMessage = nil
        infoMessage = nil

        do {
            let fetched = try await repo.listCalls(pageSize: 100)
            calls = fetched
            if fetched.isEmpty {
                infoMessage = "No calls yet. When VoIP is enabled for your account, calls will appear here."
            }
        } catch let err as APITransportError {
            if case .httpStatus(404, _) = err {
                infoMessage = "Calls not available — VoIP is not enabled for this account."
            } else {
                errorMessage = err.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Filtered views

    public var inboundCalls: [CallLogEntry] { calls.filter { $0.isInbound } }
    public var outboundCalls: [CallLogEntry] { calls.filter { !$0.isInbound } }
    /// Missed = inbound with zero duration (never answered).
    public var missedCalls: [CallLogEntry] { calls.filter { $0.isInbound && ($0.durationSeconds ?? 0) == 0 } }

    // MARK: - Initiate call

    /// Initiate a click-to-call via `POST /api/v1/voice/call`.
    /// On success, `activeOutboundCallId` is set so the UI can show an active-call banner.
    public func initiateCall(to phoneNumber: String, customerId: Int64? = nil) async {
        do {
            let callId = try await repo.initiateCall(to: phoneNumber, customerId: customerId)
            activeOutboundCallId = callId
        } catch let err as APITransportError {
            if case .httpStatus(404, _) = err {
                infoMessage = "Click-to-call is not available — VoIP not configured on the server."
            } else {
                errorMessage = "Could not start call: \(err.localizedDescription)"
            }
        } catch {
            errorMessage = "Could not start call: \(error.localizedDescription)"
        }
    }

    // MARK: - Hangup

    /// Hang up the active outbound call.
    public func hangup() async {
        guard let callId = activeOutboundCallId else { return }
        isHangingUp = true
        defer {
            isHangingUp = false
            activeOutboundCallId = nil
        }
        do {
            try await repo.hangupCall(id: callId)
        } catch {
            // Non-fatal: call may have already ended on the server side.
            // Log and ignore.
        }
        // Refresh the log so the completed call appears.
        await load()
    }

    // MARK: - Recording playback

    public func openRecordingPlayback(for entry: CallLogEntry) {
        selectedForPlayback = entry
    }

    // MARK: - Transcription

    public func openTranscription(for entry: CallLogEntry) {
        selectedForTranscript = entry
    }

    // MARK: - Helpers

    public func clearError() {
        errorMessage = nil
    }
}
