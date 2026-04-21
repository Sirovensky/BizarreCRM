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
        case success(customerId: Int64, ticketId: Int64?)
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
            let body = LeadConvertBody(createTicket: createTicket)
            let response = try await api.convertLead(id: leadId, body: body)
            // Mark lead as won via status update (fire-and-forget).
            let wonBody = LeadStatusUpdateBody(status: "won")
            try? await api.updateLeadStatus(id: leadId, body: wonBody)
            state = .success(customerId: response.customerId, ticketId: response.ticketId)
        } catch {
            AppLog.ui.error("Lead convert failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public func reset() { state = .idle }
}
