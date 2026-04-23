import Foundation
import Observation
import Core
import Networking
import Sync

@MainActor
@Observable
public final class SmsListViewModel {
    public private(set) var conversations: [SmsConversation] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    /// Exposed for `StalenessIndicator` chip in toolbar.
    public private(set) var lastSyncedAt: Date?
    /// Per-row action error shown as inline banner.
    public private(set) var actionError: String?

    @ObservationIgnored private let repo: SmsRepository
    @ObservationIgnored private let cachedRepo: SmsCachedRepository?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: SmsRepository) {
        self.repo = repo
        self.cachedRepo = repo as? SmsCachedRepository
    }

    public func load() async {
        if conversations.isEmpty { isLoading = true }
        defer { isLoading = false; isRefreshing = false }
        await fetch(force: false)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(force: true)
    }

    public func onSearchChange(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch(force: false)
        }
    }

    // MARK: - Actions

    /// Marks the thread as read; updates local conversation optimistically.
    public func markRead(phone: String) async {
        // Optimistic: zero the unread count immediately.
        conversations = conversations.map { c in
            guard c.convPhone == phone else { return c }
            return SmsConversation(
                convPhone: c.convPhone,
                lastMessageAt: c.lastMessageAt,
                lastMessage: c.lastMessage,
                lastDirection: c.lastDirection,
                messageCount: c.messageCount,
                unreadCount: 0,
                isFlagged: c.isFlagged,
                isPinned: c.isPinned,
                customer: c.customer,
                recentTicket: c.recentTicket
            )
        }
        do {
            try await repo.markRead(phone: phone)
        } catch {
            AppLog.ui.error("markRead failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
            // Revert on failure.
            await fetch(force: true)
        }
    }

    /// Toggles flag; updates local conversation optimistically.
    public func toggleFlag(phone: String) async {
        do {
            let newFlagged = try await repo.toggleFlag(phone: phone)
            conversations = conversations.map { c in
                guard c.convPhone == phone else { return c }
                return SmsConversation(
                    convPhone: c.convPhone,
                    lastMessageAt: c.lastMessageAt,
                    lastMessage: c.lastMessage,
                    lastDirection: c.lastDirection,
                    messageCount: c.messageCount,
                    unreadCount: c.unreadCount,
                    isFlagged: newFlagged,
                    isPinned: c.isPinned,
                    customer: c.customer,
                    recentTicket: c.recentTicket
                )
            }
        } catch {
            AppLog.ui.error("toggleFlag failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Toggles pin; updates local conversation and re-sorts so pinned rows surface first.
    public func togglePin(phone: String) async {
        do {
            let newPinned = try await repo.togglePin(phone: phone)
            conversations = conversations.map { c in
                guard c.convPhone == phone else { return c }
                return SmsConversation(
                    convPhone: c.convPhone,
                    lastMessageAt: c.lastMessageAt,
                    lastMessage: c.lastMessage,
                    lastDirection: c.lastDirection,
                    messageCount: c.messageCount,
                    unreadCount: c.unreadCount,
                    isFlagged: c.isFlagged,
                    isPinned: newPinned,
                    customer: c.customer,
                    recentTicket: c.recentTicket
                )
            }
            // Re-sort: pinned threads float to top (mirrors server sort in GET /conversations).
            conversations = conversations.sorted { a, b in
                if a.isPinned && !b.isPinned { return true }
                if !a.isPinned && b.isPinned { return false }
                return false
            }
        } catch {
            AppLog.ui.error("togglePin failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Clears the inline action error banner.
    public func clearActionError() {
        actionError = nil
    }

    // MARK: - Private

    private func fetch(force: Bool) async {
        errorMessage = nil
        do {
            let keyword: String? = searchQuery.isEmpty ? nil : searchQuery
            if force, let cached = cachedRepo {
                conversations = try await cached.forceRefresh(keyword: keyword)
                lastSyncedAt = await cached.lastSyncedAt
            } else if let cached = cachedRepo {
                conversations = try await cached.listConversations(keyword: keyword)
                lastSyncedAt = await cached.lastSyncedAt
            } else {
                conversations = try await repo.listConversations(keyword: keyword)
            }
        } catch {
            AppLog.ui.error("SMS list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
