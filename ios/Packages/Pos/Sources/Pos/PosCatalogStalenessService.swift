import Foundation

// MARK: - CatalogStalenessState

/// The freshness state of the POS catalog cache.
///
/// Used by `PosView` / `PosSearchPanel` to show a stop-sell warning banner
/// when any part of the catalog is stale (§16.12 "Stop-sell").
public enum CatalogStalenessState: Sendable {
    /// Catalog was refreshed within the last `maxAgeSeconds`.
    case fresh(lastRefreshed: Date)
    /// Catalog is older than `maxAgeSeconds` — cashier should be warned
    /// before proceeding with a sale.
    case stale(lastRefreshed: Date?, reason: String)
    /// Staleness has not yet been evaluated (initial state before first check).
    case unknown
}

// MARK: - PosCatalogStalenessService

/// Tracks the last-refreshed timestamp of the POS catalog and determines
/// whether the catalog is stale enough to trigger a stop-sell warning.
///
/// ## §16.12 Stop-sell rule
/// If any part of the catalog is older than `maxAge` (default 24 hours):
/// - `checkStaleness()` returns `.stale(...)`.
/// - The POS view shows a dismissible "Prices may be outdated — please sync
///   before completing this sale." banner.
/// - The cashier can still override and proceed (we never hard-block the sale
///   from the client — server re-validates on checkout).
///
/// ## Persistence
/// The last-refreshed timestamp is stored in `UserDefaults` under the key
/// `"pos.catalogLastRefreshedAt"` so it survives app restarts.
public actor PosCatalogStalenessService {

    // MARK: - Configuration

    /// Maximum catalog age before a stop-sell warning is shown (default 24 h).
    public let maxAge: TimeInterval

    // MARK: - Private state

    private let defaults: UserDefaults
    private let timestampKey = "pos.catalogLastRefreshedAt"

    // MARK: - Init

    public init(
        maxAge: TimeInterval = 24 * 60 * 60,
        defaults: UserDefaults = .standard
    ) {
        self.maxAge    = maxAge
        self.defaults  = defaults
    }

    // MARK: - Public API

    /// Record that the catalog was successfully refreshed at `date`.
    public func markRefreshed(at date: Date = .now) {
        defaults.set(date.timeIntervalSince1970, forKey: timestampKey)
    }

    /// Evaluate whether the catalog is currently stale.
    ///
    /// - Parameter now: Reference timestamp; defaults to `Date.now`.
    /// - Returns: A `CatalogStalenessState` for the caller to act on.
    public func checkStaleness(now: Date = .now) -> CatalogStalenessState {
        let raw = defaults.double(forKey: timestampKey)
        guard raw > 0 else {
            // Never been refreshed on this device — treat as stale.
            return .stale(lastRefreshed: nil, reason: "Catalog has never been synced on this device.")
        }

        let lastRefreshed = Date(timeIntervalSince1970: raw)
        let age = now.timeIntervalSince(lastRefreshed)

        if age > maxAge {
            let hoursAgo = Int(age / 3600)
            let reason = hoursAgo >= 24
                ? "Catalog is \(hoursAgo / 24)d \(hoursAgo % 24)h old — prices may be outdated."
                : "Catalog is \(hoursAgo)h old — prices may be outdated."
            return .stale(lastRefreshed: lastRefreshed, reason: reason)
        }

        return .fresh(lastRefreshed: lastRefreshed)
    }

    /// Whether the catalog is currently fresh (age < `maxAge`).
    public func isFresh(now: Date = .now) -> Bool {
        if case .fresh = checkStaleness(now: now) { return true }
        return false
    }
}

// MARK: - CatalogStalenessState helpers

public extension CatalogStalenessState {
    /// Human-readable banner text for the stop-sell warning.
    var bannerText: String? {
        switch self {
        case .stale(_, let reason): return reason
        case .fresh, .unknown:      return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
