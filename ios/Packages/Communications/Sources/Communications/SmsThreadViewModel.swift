import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class SmsThreadViewModel {
    public private(set) var thread: SmsThread?
    public private(set) var isLoading: Bool = true
    public private(set) var isSending: Bool = false
    public private(set) var errorMessage: String?
    public var draft: String = ""

    /// Set to the ID of a message that just arrived via WS so the view can
    /// scroll to bottom with a spring animation.
    public private(set) var newMessageId: Int64?

    /// §12.2 Schedule send — date/time picker for future delivery.
    /// When set, `send()` includes `send_at` in the POST body.
    public var scheduledSendAt: Date?

    /// §12.2 Compliance footer — auto-append STOP message on first outbound
    /// to opt-in-ambiguous numbers.
    /// When true the composer appends "Reply STOP to opt out" before sending.
    public var appendComplianceFooter: Bool = false

    public let phoneNumber: String

    @ObservationIgnored private let repo: SmsThreadRepository
    @ObservationIgnored var wsListenTask: Task<Void, Never>?

    public init(repo: SmsThreadRepository, phoneNumber: String) {
        self.repo = repo
        self.phoneNumber = phoneNumber
    }

    public func load() async {
        if thread == nil { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            thread = try await repo.thread(phone: phoneNumber)
        } catch {
            AppLog.ui.error("SMS thread load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func send() async {
        var trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        // §12.2 Compliance footer
        if appendComplianceFooter {
            trimmed += "\n\nReply STOP to opt out."
        }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        do {
            // §12.2 Schedule send
            if let sendAt = scheduledSendAt {
                let iso = ISO8601DateFormatter().string(from: sendAt)
                _ = try await repo.sendScheduled(to: phoneNumber, message: trimmed, sendAt: iso)
                scheduledSendAt = nil
            } else {
                _ = try await repo.send(to: phoneNumber, message: trimmed)
            }
            draft = ""
            newMessageId = nil
            await load() // refresh thread
        } catch {
            AppLog.ui.error("SMS send failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func setNewMessageId(_ id: Int64) {
        newMessageId = id
    }

    /// §12.13 Send-failed retry — re-sends the body of a failed message.
    /// The original failed message remains in the thread (server handles dedup
    /// based on idempotency key if supported; otherwise creates a new message).
    public func retrySend(message: SmsMessage) async {
        let body = message.message ?? ""
        guard !body.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        do {
            _ = try await repo.send(to: phoneNumber, message: body)
            draft = ""
            await load()
        } catch {
            AppLog.ui.error("SMS retry failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public protocol SmsThreadRepository: Sendable {
    func thread(phone: String) async throws -> SmsThread
    func send(to: String, message: String) async throws -> SmsMessage
    /// §12.2 Schedule send — posts with `send_at` ISO-8601 timestamp.
    func sendScheduled(to: String, message: String, sendAt: String) async throws -> SmsMessage
}

public actor SmsThreadRepositoryImpl: SmsThreadRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func thread(phone: String) async throws -> SmsThread {
        try await api.smsThread(phone: phone)
    }

    public func send(to: String, message: String) async throws -> SmsMessage {
        try await api.sendSms(to: to, message: message)
    }

    public func sendScheduled(to: String, message: String, sendAt: String) async throws -> SmsMessage {
        try await api.sendSmsScheduled(to: to, message: message, sendAt: sendAt)
    }
}
