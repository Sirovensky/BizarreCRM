import Foundation

// §29.3 Image cache — tiered eviction policy.
//
// The earlier §29.3 note said "not blunt LRU". This file codifies the ordered
// eviction tiers so that the background `BGProcessingTask` cleanup job (and any
// Settings-triggered manual clear) uses the same priority logic everywhere.
//
// Eviction order (cheapest-to-lose first):
//   1. Archived-ticket photos — the ticket is closed; user rarely revisits.
//   2. Photos not viewed in > 30 days AND older than 90 days.
//   3. Unviewed full-res photos (downloaded speculatively; never opened in detail).
//   4. Thumbnails (last resort — tiny, cheap to re-fetch).
//   5. Pinned-offline photos — NEVER auto-evicted regardless of pressure.
//
// The policy is a pure-Swift value type. The actual disk traversal is performed
// by the app-layer `StorageMonitor` / `BGProcessingTask`; this file only defines
// the classification and priority ranking used to drive those passes.

// MARK: - EvictionTier

/// Priority tier for image-cache eviction, ordered from least valuable (evict
/// first) to most valuable (never evict).
public enum EvictionTier: Int, Comparable, Sendable {
    /// Archived-ticket attachments — ticket is closed; safe to drop first.
    case archivedTicket     = 1
    /// Old full-res photos: older than `ageThresholdDays` AND last viewed more
    /// than `viewedThresholdDays` ago.
    case oldUnviewed        = 2
    /// Full-res photos fetched speculatively but never opened in detail view.
    case speculativeFetch   = 3
    /// Thumbnail-size images — tiny; evict before abandoning full-res pinned items.
    case thumbnail          = 4
    /// Pinned-offline photos — user explicitly pinned or system pinned because
    /// the parent ticket is still active. Never evicted automatically.
    case pinnedOffline      = 5

    public static func < (lhs: EvictionTier, rhs: EvictionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - ImageCacheEvictionPolicy

/// Classifies a cached image entry into an ``EvictionTier`` using the §29.3
/// tiered-retention model.
///
/// ## Usage
/// ```swift
/// let tier = ImageCacheEvictionPolicy.classify(entry: entry, now: .now)
/// if tier < .pinnedOffline {
///     // Safe to evict when over the disk cap.
/// }
/// ```
public enum ImageCacheEvictionPolicy: Sendable {

    // MARK: - Thresholds (§29.3)

    /// Photos not viewed within this many days AND older than `ageThresholdDays`
    /// are promoted to the `.oldUnviewed` tier.
    public static let viewedThresholdDays: Int = 30

    /// Minimum age (days) before a photo can be classified as "old" even if not
    /// viewed recently.
    public static let ageThresholdDays: Int = 90

    // MARK: - Public API

    /// Classifies a cached image entry into an eviction tier.
    ///
    /// - Parameters:
    ///   - entry: Metadata describing the cached image.
    ///   - now: The reference point for age/viewed-recency calculations.
    ///         Defaults to `Date.now` but injectable for testing.
    /// - Returns: The ``EvictionTier`` that should govern this entry's priority.
    public static func classify(entry: CachedImageEntry, now: Date = .now) -> EvictionTier {
        // Pinned items are never auto-evicted regardless of any other condition.
        if entry.isPinnedOffline { return .pinnedOffline }

        // Thumbnails: low individual cost — evict before speculative full-res
        // images but after the truly stale full-res entries.
        if entry.isThumbnail { return .thumbnail }

        // Archived ticket attachments are safe to drop early.
        if entry.parentTicketIsArchived { return .archivedTicket }

        let calendar = Calendar.current
        let ageInDays = calendar.dateComponents([.day], from: entry.cachedAt, to: now).day ?? 0
        let daysSinceViewed = calendar.dateComponents([.day], from: entry.lastViewedAt ?? entry.cachedAt, to: now).day ?? 0

        // Old + unviewed: both conditions must be true.
        if ageInDays >= ageThresholdDays && daysSinceViewed >= viewedThresholdDays {
            return .oldUnviewed
        }

        // Speculative: downloaded but never opened in detail (lastViewedAt is nil
        // and it's NOT a thumbnail and NOT old enough for `.oldUnviewed`).
        if entry.lastViewedAt == nil { return .speculativeFetch }

        // Default: recently viewed full-res — preserve until the disk cap
        // forces eviction of lower-priority tiers first.
        return .thumbnail
    }

    /// Returns `true` when an entry **may** be automatically evicted under the
    /// §29.3 policy (i.e. it is not pinned offline).
    public static func isAutoEvictable(entry: CachedImageEntry, now: Date = .now) -> Bool {
        classify(entry: entry, now: now) < .pinnedOffline
    }

    /// Sorts `entries` so the cheapest-to-evict appear first.
    ///
    /// Within the same tier, entries are sorted oldest-cached-first so that
    /// stale data is removed before recent additions.
    public static func sorted(_ entries: [CachedImageEntry], now: Date = .now) -> [CachedImageEntry] {
        entries.sorted { a, b in
            let tierA = classify(entry: a, now: now)
            let tierB = classify(entry: b, now: now)
            if tierA != tierB { return tierA < tierB }
            return a.cachedAt < b.cachedAt
        }
    }
}

// MARK: - CachedImageEntry

/// Lightweight metadata record describing a single cached image.
///
/// The actual bytes live on disk (Nuke DataCache / `offline_pinned/`). This
/// struct is all the eviction policy needs to classify an entry — it does **not**
/// hold image data.
public struct CachedImageEntry: Sendable, Equatable {

    // MARK: - Identity

    /// Opaque cache key (usually the original URL string or a hash thereof).
    public let key: String

    /// Size of the cached entry on disk, in bytes.
    public let sizeBytes: Int

    // MARK: - Classification flags

    /// Whether this entry is a thumbnail-sized image (as opposed to full-res).
    public let isThumbnail: Bool

    /// Whether the parent ticket/entity has been archived.
    public let parentTicketIsArchived: Bool

    /// Whether the user (or system) has pinned this image for offline use.
    public let isPinnedOffline: Bool

    // MARK: - Temporal metadata

    /// When the image was first written to the disk cache.
    public let cachedAt: Date

    /// When the image was last presented in a detail / gallery view.
    /// `nil` means it was downloaded speculatively but never viewed full-size.
    public let lastViewedAt: Date?

    // MARK: - Init

    public init(
        key: String,
        sizeBytes: Int,
        isThumbnail: Bool,
        parentTicketIsArchived: Bool,
        isPinnedOffline: Bool,
        cachedAt: Date,
        lastViewedAt: Date? = nil
    ) {
        self.key = key
        self.sizeBytes = sizeBytes
        self.isThumbnail = isThumbnail
        self.parentTicketIsArchived = parentTicketIsArchived
        self.isPinnedOffline = isPinnedOffline
        self.cachedAt = cachedAt
        self.lastViewedAt = lastViewedAt
    }
}
