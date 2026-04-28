import Foundation

// §29.3 — Storage diagnostics panel (Settings → Data).
//
// Provides a live breakdown of on-device storage consumed by the app:
//   • SQLCipher DB (GRDB pool file)
//   • Image thumbnail cache (Nuke memory + disk)
//   • Full-resolution image cache
//   • Pinned-offline attachments
//   • Drafts store
//   • Export temp files
//
// Rules (§20.9 / §29.3):
//   - Thumbnails always cached; never auto-evicted.
//   - Full-res LRU with tenant-size-scaled cap (default 2 GB; user 500 MB–20 GB
//     or no-limit). Configurable via `ImageCachePolicy.maxFullResCacheBytes`.
//   - Pinned-offline store + active-ticket photos never auto-evicted.
//   - Cleanup runs at most once per 24h in a `BGProcessingTask`.
//   - Warn only on device-low-disk (< 2 GB free), not on app-cache growth alone.
//   - Never evict pinned or in-use items to satisfy the guard.

// MARK: - StorageCategory

/// Logical storage categories measured by `StorageMonitor`.
public enum StorageCategory: String, CaseIterable, Sendable {
    /// SQLCipher GRDB pool file (per-tenant, encrypted).
    case database          = "database"
    /// Nuke thumbnail cache (memory + disk).
    case thumbnailCache    = "thumbnail_cache"
    /// Full-resolution image cache (disk LRU).
    case fullResCache      = "full_res_cache"
    /// Photos + PDFs pinned for offline use on active tickets.
    case pinnedAttachments = "pinned_attachments"
    /// Auto-saved draft files (ticket create / customer create / SMS compose).
    case drafts            = "drafts"
    /// Temp export zips and generated PDFs awaiting share or deletion.
    case exportTemp        = "export_temp"

    /// Human-readable display name (English; callers should localise).
    public var displayName: String {
        switch self {
        case .database:          return "Database"
        case .thumbnailCache:    return "Thumbnail cache"
        case .fullResCache:      return "Full-resolution cache"
        case .pinnedAttachments: return "Pinned attachments"
        case .drafts:            return "Drafts"
        case .exportTemp:        return "Export files"
        }
    }

    /// Whether this category is safe to evict automatically.
    ///
    /// `false` = never auto-evict; requires explicit user action.
    public var isEvictable: Bool {
        switch self {
        case .fullResCache, .exportTemp: return true
        case .database, .thumbnailCache, .pinnedAttachments, .drafts: return false
        }
    }
}

// MARK: - StorageItem

/// A single measured storage item.
public struct StorageItem: Sendable {
    public let category: StorageCategory
    /// Size in bytes at time of measurement.
    public let bytes: Int64
    /// When this measurement was taken.
    public let measuredAt: Date

    public init(category: StorageCategory, bytes: Int64, measuredAt: Date = .now) {
        self.category = category
        self.bytes = bytes
        self.measuredAt = measuredAt
    }

    /// Formatted size string (e.g. "1.2 GB", "45 MB").
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - StorageBreakdown

/// A snapshot of all storage categories measured at a point in time.
public struct StorageBreakdown: Sendable {
    public let items: [StorageItem]
    public let measuredAt: Date

    public init(items: [StorageItem], measuredAt: Date = .now) {
        self.items = items
        self.measuredAt = measuredAt
    }

    /// Total bytes across all categories.
    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }

    /// Item for a specific category, or `nil` if not measured.
    public func item(for category: StorageCategory) -> StorageItem? {
        items.first { $0.category == category }
    }

    /// Evictable bytes — space that could be freed without user impact.
    public var evictableBytes: Int64 {
        items.filter { $0.category.isEvictable }.reduce(0) { $0 + $1.bytes }
    }

    /// Formatted total size string.
    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

// MARK: - ImageCachePolicy

/// §29.3 Image cache eviction policy.
///
/// Controls the full-resolution LRU cache cap. Thumbnails are never
/// subject to this limit.
///
/// Configure once via `ImageCachePolicy.configure(maxBytes:)` from
/// `AppServices` at launch (after loading tenant preferences if the
/// tenant customises this limit).
public final class ImageCachePolicy: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = ImageCachePolicy()

    // MARK: - Constants

    /// Minimum allowed full-res cache size (500 MB).
    public static let minimumBytes: Int64 = 500 * 1_024 * 1_024

    /// Default full-res cache size (2 GB).
    public static let defaultBytes: Int64 = 2 * 1_024 * 1_024 * 1_024

    /// Maximum allowed full-res cache size (20 GB).
    public static let maximumBytes: Int64 = 20 * 1_024 * 1_024 * 1_024

    // MARK: - State

    private var _maxFullResCacheBytes: Int64 = ImageCachePolicy.defaultBytes

    /// Current full-res cache cap in bytes.
    public var maxFullResCacheBytes: Int64 {
        get { _maxFullResCacheBytes }
    }

    // MARK: - Init

    private init() {}

    // MARK: - Configuration

    /// Sets the full-res cache limit, clamped to [500 MB, 20 GB].
    ///
    /// Pass `nil` to restore the default (2 GB).
    ///
    /// - Parameter maxBytes: Desired cap in bytes, or `nil` for default.
    public func configure(maxBytes: Int64?) {
        let capped = maxBytes.map {
            max(ImageCachePolicy.minimumBytes, min($0, ImageCachePolicy.maximumBytes))
        } ?? ImageCachePolicy.defaultBytes
        _maxFullResCacheBytes = capped
    }

    // MARK: - Low-disk guard

    /// Threshold for device free-space low-disk warning (2 GB).
    public static let lowDiskThresholdBytes: Int64 = 2 * 1_024 * 1_024 * 1_024

    /// Returns `true` when available device storage is below the low-disk threshold.
    ///
    /// Call from the nightly `BGProcessingTask` before eviction; if the device
    /// isn't low on space, skip full eviction and only purge export temp files.
    public func isDeviceLowOnDisk() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ),
        let free = attrs[.systemFreeSize] as? Int64
        else { return false }
        return free < ImageCachePolicy.lowDiskThresholdBytes
    }
}

// MARK: - StorageMonitor

/// §29.3 Measures on-device storage for each `StorageCategory`.
///
/// This is a lightweight file-size scanner. It does **not** access the
/// Nuke image cache directly — callers that integrate Nuke should inject
/// Nuke's `DataCache.size` and `ImageCache.totalCost` via the `inject`
/// parameter on `measure(inject:)`.
public struct StorageMonitor: Sendable {

    // MARK: - Public API

    /// Measures all categories and returns a `StorageBreakdown`.
    ///
    /// - Parameter inject: Optional overrides (e.g., Nuke cache sizes).
    ///   Key = `StorageCategory.rawValue`, value = size in bytes.
    public func measure(inject: [String: Int64] = [:]) async -> StorageBreakdown {
        var items: [StorageItem] = []
        let now = Date.now

        for category in StorageCategory.allCases {
            if let injected = inject[category.rawValue] {
                items.append(StorageItem(category: category, bytes: injected, measuredAt: now))
            } else {
                let bytes = await measureCategory(category)
                items.append(StorageItem(category: category, bytes: bytes, measuredAt: now))
            }
        }
        return StorageBreakdown(items: items, measuredAt: now)
    }

    // MARK: - Internals

    private func measureCategory(_ category: StorageCategory) async -> Int64 {
        switch category {
        case .database:
            return await sizeOfFiles(inDirectory: applicationSupportDirectory,
                                     matching: { $0.hasSuffix(".sqlite") || $0.hasSuffix(".db") })
        case .thumbnailCache:
            // Thumbnails live in Library/Caches/thumbnails/ (caller-managed by Nuke).
            return await sizeOfDirectory(named: "thumbnails", under: cachesDirectory)
        case .fullResCache:
            return await sizeOfDirectory(named: "fullres", under: cachesDirectory)
        case .pinnedAttachments:
            return await sizeOfDirectory(named: "pinned_attachments", under: applicationSupportDirectory)
        case .drafts:
            return await sizeOfFiles(inDirectory: applicationSupportDirectory,
                                     matching: { $0.hasSuffix(".draft") })
        case .exportTemp:
            return await sizeOfDirectory(named: "exports", under: temporaryDirectory)
        }
    }

    // MARK: - Helpers

    private var applicationSupportDirectory: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        )
    }

    private var cachesDirectory: URL? {
        try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        )
    }

    private var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private func sizeOfDirectory(named name: String, under parent: URL?) async -> Int64 {
        guard let dir = parent?.appendingPathComponent(name) else { return 0 }
        return totalSize(at: dir)
    }

    private func sizeOfFiles(inDirectory dir: URL?, matching predicate: (String) -> Bool) async -> Int64 {
        guard let dir else { return 0 }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard predicate(url.lastPathComponent) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    private func totalSize(at dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
