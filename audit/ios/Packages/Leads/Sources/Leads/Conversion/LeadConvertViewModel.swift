import Foundation
import Observation
import Core
import Networking

// MARK: - LeadConvertViewModel

@MainActor
@Observable
public final class LeadConvertViewModel {

    public enum State: Sendable {
        case idle
        case submitting
        /// Conversion succeeded; ticket has been created.
        case success(ticketId: Int64, customerId: Int64?)
        case failed(String)

        public var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        public var isSubmitting: Bool {
            if case .submitting = self { return true }
            return false
        }
    }

    public var createTicket: Bool = false
    public private(set) var state: State = .idle

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let leadId: Int64

    public init(api: APIClient, leadId: Int64) {
        self.api = api
        self.leadId = leadId
    }

    public func convert() async {
        guard case .idle = state else { return }
        state = .submitting
        do {
            // The convert endpoint always sends `createTicket: true` effectively
            // because the server always creates a ticket on conversion.
            // The `createTicket` flag is kept in the body for API contract completeness.
            let body = LeadConvertBody(createTicket: createTicket)
            let response = try await api.convertLead(id: leadId, body: body)
            // Server transitions the lead to 'converted' automatically; no
            // additional status PATCH needed.
            state = .success(ticketId: response.ticketId, customerId: response.customerId)
        } catch {
            AppLog.ui.error("Lead convert failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public func reset() { state = .idle }
}
