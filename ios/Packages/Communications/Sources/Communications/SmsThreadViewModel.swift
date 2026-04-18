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

    public let phoneNumber: String

    @ObservationIgnored private let repo: SmsThreadRepository

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
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        do {
            _ = try await repo.send(to: phoneNumber, message: trimmed)
            draft = ""
            await load() // refresh thread
        } catch {
            AppLog.ui.error("SMS send failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public protocol SmsThreadRepository: Sendable {
    func thread(phone: String) async throws -> SmsThread
    func send(to: String, message: String) async throws -> SmsMessage
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
}
