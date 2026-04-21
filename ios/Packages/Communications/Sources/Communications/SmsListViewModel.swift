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
