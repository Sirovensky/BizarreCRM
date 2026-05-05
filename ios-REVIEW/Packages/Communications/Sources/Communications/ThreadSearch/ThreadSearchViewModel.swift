import Foundation
import Observation
import Networking
import Core

// MARK: - ThreadSearchResult

public struct ThreadSearchResult: Identifiable, Sendable, Hashable {
    public let id: Int64
    public let messageId: Int64
    public let snippet: String
    public let createdAt: String?
    /// The search query that produced this result, used by the view for inline highlight.
    public let query: String

    public init(messageId: Int64, snippet: String, query: String, createdAt: String?) {
        self.id = messageId
        self.messageId = messageId
        self.snippet = snippet
        self.createdAt = createdAt
        self.query = query
    }
}

// MARK: - ThreadSearchViewModel

/// Debounced search within a single SMS thread (local message list + server endpoint).
@MainActor
@Observable
public final class ThreadSearchViewModel: Sendable {

    // MARK: - State

    public var query: String = "" {
        didSet { scheduleSearch() }
    }
    public private(set) var results: [ThreadSearchResult] = []
    public private(set) var isSearching: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Dependencies

    @ObservationIgnored private let threadId: String
    @ObservationIgnored private let localMessages: [SmsMessage]
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    private let debounceInterval: Duration = .milliseconds(300)

    // MARK: - Init

    public init(threadId: String, localMessages: [SmsMessage], api: APIClient) {
        self.threadId = threadId
        self.localMessages = localMessages
        self.api = api
    }

    // MARK: - Search

    private func scheduleSearch() {
        debounceTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self.performSearch()
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        // Local in-memory filter (FTS5 via GRDB wired in §18)
        let localResults = localMessages.compactMap { msg -> ThreadSearchResult? in
            guard let text = msg.message, text.localizedCaseInsensitiveContains(trimmed) else { return nil }
            return ThreadSearchResult(messageId: msg.id, snippet: text, query: trimmed, createdAt: msg.createdAt)
        }

        // Server search (best-effort; falls back to local if offline)
        do {
            let resp = try await api.get(
                "/api/v1/sms/threads/\(threadId)/search",
                query: [URLQueryItem(name: "q", value: trimmed)],
                as: ThreadSearchResponse.self
            )
            let serverResults = resp.results.map { r in
                ThreadSearchResult(messageId: r.messageId, snippet: r.snippet, query: trimmed, createdAt: r.createdAt)
            }
            // Merge, deduplicating by messageId; server results take priority
            var seen = Set<Int64>()
            results = (serverResults + localResults).filter { seen.insert($0.messageId).inserted }
        } catch {
            // Offline — local results only
            results = localResults
            if localResults.isEmpty {
                AppLog.ui.error("ThreadSearch server: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func clear() {
        query = ""
        results = []
    }
}

// MARK: - Server response types

private struct ThreadSearchResponse: Decodable, Sendable {
    let results: [ServerSearchResult]

    struct ServerSearchResult: Decodable, Sendable {
        let messageId: Int64
        let snippet: String
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case snippet
            case createdAt = "created_at"
        }
    }
}
