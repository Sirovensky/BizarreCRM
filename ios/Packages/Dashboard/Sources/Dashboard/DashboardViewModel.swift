import Foundation
import Observation
import Core
import Networking
import DesignSystem

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
            if let cached = cachedRepo {
                lastSyncedAt = await cached.lastSyncedAt
            }
        } catch {
            AppLog.ui.error("Dashboard load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Called by `.refreshable` — always fetches fresh data when cache-aware.
    /// Fires a `.pullToRefresh` haptic (§3.1) at the moment data lands so the
    /// user gets tactile confirmation the content actually updated.
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
                lastSyncedAt = await cached.lastSyncedAt
                // §3.1 — haptic acknowledges that fresh data has arrived.
                await HapticCatalog.play(.pullToRefresh)
            } catch {
                AppLog.ui.error("Dashboard force-refresh failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        } else {
            await load()
        }
    }
}
