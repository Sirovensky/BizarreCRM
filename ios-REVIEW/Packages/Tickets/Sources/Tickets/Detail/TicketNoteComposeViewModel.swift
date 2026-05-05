import Foundation
import Observation
import Core
import Networking

// §4.6 — Note compose view model (platform-agnostic).
// Separated from TicketNoteComposeView so macOS test targets can test it.

@MainActor
@Observable
public final class TicketNoteComposeViewModel {
    public var type: NoteType = .internal_
    public var content: String = ""
    public var isFlagged: Bool = false
    public var deviceId: Int64? = nil

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didPost: Bool = false

    public enum NoteType: String, CaseIterable, Sendable, Identifiable {
        case internal_   = "internal"
        case customer    = "customer"
        case diagnostic  = "diagnostic"
        case sms         = "sms"
        case email       = "email"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .internal_:  return "Internal"
            case .customer:   return "Customer visible"
            case .diagnostic: return "Diagnostic"
            case .sms:        return "SMS"
            case .email:      return "Email"
            }
        }

        public var systemImage: String {
            switch self {
            case .internal_:  return "lock.fill"
            case .customer:   return "person.fill"
            case .diagnostic: return "stethoscope"
            case .sms:        return "message.fill"
            case .email:      return "envelope.fill"
            }
        }
    }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ticketId: Int64

    public init(api: APIClient, ticketId: Int64) {
        self.api = api
        self.ticketId = ticketId
    }

    public var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func post() async {
        guard !isSubmitting, isValid else {
            if !isValid { errorMessage = "Note content cannot be empty." }
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let req = AddTicketNoteRequest(
            type: type.rawValue,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            isFlagged: isFlagged,
            ticketDeviceId: deviceId
        )

        do {
            _ = try await api.addTicketNote(ticketId: ticketId, req)
            didPost = true
        } catch {
            AppLog.ui.error("Note post failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
        }
    }
}
