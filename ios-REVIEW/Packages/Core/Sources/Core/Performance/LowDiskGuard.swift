import Foundation
import Observation

// §20.9 — Low-disk pause
//
// Freezes writes to non-essential caches (full-resolution images, export temp
// files, draft autosave snapshots) when device free space drops below 2 GB.
// Resumes automatically when free space climbs back above the threshold.
//
// Pinned items, the SQLCipher GRDB DB, and in-flight sync queue writes are
// **never** evicted to satisfy the guard — those are tenant-critical data.
//
// Usage:
//
//   if !LowDiskGuard.shared.allowsCacheWrites {
//       AppLog.cache.warning("Skipping cache write: low disk")
//       return
//   }
//
// Refresh from a `BGAppRefreshTask` and on `didBecomeActive`:
//
//   await LowDiskGuard.shared.refresh()

@Observable
@MainActor
public final class LowDiskGuard {

    public static let shared = LowDiskGuard()

    /// Last measured free bytes on the home directory volume.
    public private(set) var freeBytes: Int64 = 0

    /// `true` while free space is below `lowDiskThresholdBytes`. UI surfaces a
    /// toast ("Free up space — app cache paused") while this is `true`.
    public private(set) var isPaused: Bool = false

    /// When the last refresh ran. `nil` until the first `refresh()` call.
    public private(set) var lastCheckedAt: Date?

    private init() {}

    // MARK: - API

    /// Whether non-essential cache writes are currently allowed. Calls in hot
    /// paths can read this synchronously without a `refresh()` first.
    public var allowsCacheWrites: Bool { !isPaused }

    /// Re-measure device free space and update `isPaused` accordingly.
    /// Cheap (one `attributesOfFileSystem` call); safe to call from any
    /// foreground transition or background task.
    public func refresh() {
        let bytes = Self.measureFreeBytes()
        freeBytes = bytes
        isPaused = bytes < ImageCachePolicy.lowDiskThresholdBytes
        lastCheckedAt = Date()
    }

    // MARK: - Internal

    private static func measureFreeBytes() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ),
        let free = attrs[.systemFreeSize] as? Int64
        else { return Int64.max }   // unknown → don't pause unnecessarily
        return free
    }
}
