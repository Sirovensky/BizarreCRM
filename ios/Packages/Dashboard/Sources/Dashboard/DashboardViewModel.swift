import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class DashboardViewModel {
    public enum State: Sendable {
        case loading
        case loaded(DashboardSnapshot)
        case failed(String)
    }

    public var state: State = .loading
    /// Exposed for `StalenessIndicator` in the toolbar.
    public var lastSyncedAt: Date?

    // §3.14 Network fail → keep cached KPIs visible.
    // When a load fails, `cachedSnapshot` holds the last successfully loaded
    // data so the view can render it with a "Showing cached data" banner.
    public private(set) var cachedSnapshot: DashboardSnapshot?
    public private(set) var loadError: String?

    @ObservationIgnored private let repo: DashboardRepository
    /// Non-nil when repo is cache-aware (used by forceRefresh on pull-to-refresh).
    @ObservationIgnored private let cachedRepo: DashboardCachedRepository?

    public init(repo: DashboardRepository) {
        self.repo = repo
        self.cachedRepo = repo as? DashboardCachedRepository
    }

    public func load() async {
        if case .loaded = state {
            // Keep current data visible while re-fetching (soft refresh).
        } else {
            state = .loading
        }

        // Read lastSyncedAt before the fetch so the chip updates on success.
        if let cached = cachedRepo {
            lastSyncedAt = await cached.lastSyncedAt
        }

        do {
            let snapshot = try await repo.load()
            state = .loaded(snapshot)
            cachedSnapshot = snapshot   // §3.14: persist for failure fallback
            loadError = nil
            if let cached = cachedRepo {
                lastSyncedAt = await cached.lastSyncedAt
            }
        } catch {
            AppLog.ui.error("Dashboard load failed: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
            // §3.14: if we have a prior snapshot, stay in loaded state with stale banner.
            if let prior = cachedSnapshot {
                state = .loaded(prior)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Called by `.refreshable` — always fetches fresh data when cache-aware.
    public func forceRefresh() async {
        if let cached = cachedRepo {
            if case .loaded = state {
                // Keep visible while refreshing.
            } else {
                state = .loading
            }
            do {
                let snapshot = try await cached.forceRefresh()
                state = .loaded(snapshot)
                cachedSnapshot = snapshot
                loadError = nil
                lastSyncedAt = await cached.lastSyncedAt
            } catch {
                AppLog.ui.error("Dashboard force-refresh failed: \(error.localizedDescription, privacy: .public)")
                loadError = error.localizedDescription
                if let prior = cachedSnapshot {
                    state = .loaded(prior)
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        } else {
            await load()
        }
    }
}
