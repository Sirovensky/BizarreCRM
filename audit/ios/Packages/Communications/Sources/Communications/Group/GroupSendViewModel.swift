import Foundation
import Observation
import Networking
import Core

// MARK: - GroupSendViewModel

/// Composes and batch-sends a single message to N recipients individually.
/// Each recipient gets its own thread; the server creates them.
@MainActor
@Observable
public final class GroupSendViewModel: Sendable {

    // MARK: - State

    public var recipients: [String] = []
    public var body: String = ""
    public var scheduledAt: Date? = nil

    public private(set) var isSending: Bool = false
    public private(set) var didSend: Bool = false
    public private(set) var progress: Double = 0.0
    public private(set) var errorMessage: String?
    public private(set) var lastAck: GroupSendAck?

    // MARK: - Derived

    public var canSend: Bool {
        !recipients.isEmpty && !body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var recipientCountLabel: String {
        "\(recipients.count) recipient\(recipients.count == 1 ? "" : "s")"
    }

    public var estimatedCostLabel: String {
        // Rough estimate: 1 SMS segment per recipient, 160 chars.
        let segments = Int(ceil(Double(body.count) / 160.0))
        return "\(recipients.count * max(1, segments)) SMS segment\(recipients.count * max(1, segments) == 1 ? "" : "s")"
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Recipient management

    public func addRecipient(_ phone: String) {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !recipients.contains(trimmed) else { return }
        recipients.append(trimmed)
    }

    public func removeRecipient(_ phone: String) {
        recipients.removeAll { $0 == phone }
    }

    // MARK: - Send

    public func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        didSend = false
        errorMessage = nil
        progress = 0.0
        defer { isSending = false }

        let scheduledStr = scheduledAt.map { iso8601String(from: $0) }
        let req = GroupSendRequest(recipients: recipients, body: body, scheduledAt: scheduledStr)

        do {
            progress = 0.3
            let ack = try await api.groupSend(request: req)
            lastAck = ack
            progress = 1.0
            didSend = true
        } catch {
            AppLog.ui.error("GroupSend failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            progress = 0.0
        }
    }

    // MARK: - Helpers

    private func iso8601String(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
