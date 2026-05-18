import Foundation
import SwiftUI
import Networking
import Core

// MARK: - TeamChatViewModel
//
// §14.5 — Channel-less team chat. Loads the seeded "general" channel,
// polls every 4 s for new messages, exposes a composer + pin/delete actions.

@MainActor
@Observable
public final class TeamChatViewModel {
    public private(set) var channel: TeamChannelRow?
    public private(set) var messages: [TeamMessageRow] = []
    public private(set) var pinnedIds: Set<Int64> = []
    public private(set) var isLoading = false
    public private(set) var isSending = false
    public private(set) var errorMessage: String?

    public var draftBody: String = ""
    public var pendingAttachment: TeamChatAttachment?

    @ObservationIgnored private let repo: TeamChatRepository
    @ObservationIgnored private let pinStore: PinnedMessagesStore
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let pollInterval: UInt64 = 4_000_000_000 // 4 s

    public init(repo: TeamChatRepository, pinStore: PinnedMessagesStore = UserDefaultsPinnedMessagesStore()) {
        self.repo = repo
        self.pinStore = pinStore
    }

    public func start() async {
        await loadInitial()
        startPolling()
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let ch = try await repo.ensureGeneralChannel()
            self.channel = ch
            self.pinnedIds = pinStore.pinnedIds(channelId: ch.id)
            let rows = try await repo.listMessages(channelId: ch.id, after: 0)
            self.messages = rows
        } catch {
            AppLog.ui.error("TeamChat load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.pollInterval)
                if Task.isCancelled { break }
                await self.pollOnce()
            }
        }
    }

    private func pollOnce() async {
        guard let ch = channel else { return }
        let lastId = messages.last?.id ?? 0
        do {
            let new = try await repo.listMessages(channelId: ch.id, after: lastId)
            if !new.isEmpty {
                messages.append(contentsOf: new)
            }
        } catch {
            // Polling failures are silent — connection blips happen.
        }
    }

    public func send() async {
        guard let ch = channel else { return }
        // BUGHUNT-2026-05-17: re-entry guard. Rapid double-taps on the Send
        // button (especially with a sluggish network) fire two postMessage
        // calls, producing two duplicate messages in the channel feed.
        guard !isSending else { return }
        let trimmed = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let attach = pendingAttachment {
            body = TeamChatAttachmentEncoder.encode(body: trimmed, attachment: attach)
        } else {
            guard !trimmed.isEmpty else { return }
            body = trimmed
        }
        isSending = true
        defer { isSending = false }
        do {
            let row = try await repo.postMessage(channelId: ch.id, body: body)
            messages.append(row)
            draftBody = ""
            pendingAttachment = nil
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: postMessage POST may have already landed.
            // Painting "cancelled" as errorMessage tempts a retap that
            // sends a duplicate message — the polling loop will eventually
            // pull both. Suppress; keep the draft so the user can decide
            // to retype intentionally if needed.
            errorMessage = nil
        } catch {
            AppLog.ui.error("TeamChat send failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func togglePin(_ message: TeamMessageRow) {
        guard let ch = channel else { return }
        let nowPinned = pinStore.togglePin(channelId: ch.id, messageId: message.id)
        if nowPinned {
            pinnedIds.insert(message.id)
        } else {
            pinnedIds.remove(message.id)
        }
    }

    public func isPinned(_ message: TeamMessageRow) -> Bool {
        pinnedIds.contains(message.id)
    }

    public var pinnedMessages: [TeamMessageRow] {
        messages.filter { pinnedIds.contains($0.id) }
    }

    public func delete(_ message: TeamMessageRow) async {
        guard let ch = channel else { return }
        do {
            try await repo.deleteMessage(channelId: ch.id, messageId: message.id)
            messages.removeAll { $0.id == message.id }
            pinnedIds.remove(message.id)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: deleteMessage may have landed already.
            // Painting "cancelled" tempts a retap that 404s on the
            // already-deleted message. Suppress and let the polling loop
            // catch up to remove the message from the local list when the
            // server has it gone.
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Parsed @username mentions in the draft body — useful for the composer
    /// chip strip preview. Mirrors server `parseMentionUsernames` regex.
    public var draftMentions: [String] {
        Self.parseMentions(in: draftBody)
    }

    static func parseMentions(in body: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        let pattern = #"@([a-zA-Z0-9_.\-]{2,32})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        regex.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let m = match, m.numberOfRanges > 1 else { return }
            let token = ns.substring(with: m.range(at: 1)).lowercased()
            if !seen.contains(token) {
                seen.insert(token)
                out.append(token)
            }
        }
        return out
    }
}
