import Foundation

// §29.3 Image loading — image-cache size configuration.
//
// Provides a typed value object that carries the three tuneable cache limits:
//   • memoryBytes  — in-process Nuke ImageCache (fast-scroll thumbnail layer)
//   • thumbDiskBytes — Nuke disk cache for thumbnails (~20 KB each; huge cap)
//   • fullResDiskBytes — Nuke disk cache for full-resolution photos (LRU)
//
// Default values follow the §29.3 spec.  `ImageCacheSizeConfig.forTenantSize(_:)`
// maps the `/auth/me` `tenant_size` hint to a recommended config; the user can
// override via Settings → Data → Storage limit.
//
// This file intentionally has no dependency on Nuke — it is pure Foundation so
// the Core package does not pull in the image-pipeline dependency.  Consumers
// (typically a Nuke bootstrap helper at the app layer) read these values and
// apply them to `ImagePipeline.Configuration`.

// MARK: - Tenant size hint

/// Tenant size hint returned by `/auth/me` (`tenant_size`).
///
/// Maps to recommended initial cache caps per §29.3.
public enum TenantSizeHint: String, Sendable, Codable {
    case small  = "s"
    case medium = "m"
    case large  = "l"
    case xlarge = "xl"
}

// MARK: - ImageCacheSizeConfig

/// Holds the three tuneable image-cache size limits (all in bytes).
///
/// ## Usage
/// ```swift
/// let config = ImageCacheSizeConfig.forTenantSize(.medium)
/// // Apply to Nuke at app start:
/// ImageCache.shared.costLimit = config.memoryBytes
/// DataLoader.sharedUrlCache.diskCapacity = 0   // Nuke manages disk itself
/// ```
///
/// All properties are `nonisolated(unsafe)` so they can be written from any
/// actor during app start-up before any concurrent readers exist.
public struct ImageCacheSizeConfig: Sendable, Equatable {

    // MARK: - Limits

    /// Maximum bytes kept in the in-process Nuke `ImageCache` (fast-scroll layer).
    ///
    /// Flushed on `didReceiveMemoryWarning` (§29.6 / `MemoryWarningFlusher`).
    /// Default: 80 MB.
    public var memoryBytes: Int

    /// Maximum bytes for the Nuke thumbnail disk cache.
    ///
    /// Thumbnails are cheap to re-fetch so this cap is generous.
    /// Default: 500 MB (≈25 000 thumbnails at 20 KB each).
    public var thumbDiskBytes: Int

    /// Maximum bytes for the Nuke full-resolution disk cache (LRU).
    ///
    /// LRU eviction kicks in when this cap is exceeded.  Pinned-offline
    /// attachments are excluded from this budget.
    /// Default: 2 GB.
    public var fullResDiskBytes: Int

    // MARK: - Hard limits

    /// Minimum configurable full-res disk cap (500 MB), per §29.3 spec.
    public static let fullResMinBytes: Int = 500 * 1024 * 1024       // 500 MB

    /// Maximum configurable full-res disk cap (20 GB), per §29.3 spec.
    public static let fullResMaxBytes: Int = 20 * 1024 * 1024 * 1024 // 20 GB

    // MARK: - Initialiser

    public init(
        memoryBytes: Int    = 80 * 1024 * 1024,
        thumbDiskBytes: Int = 500 * 1024 * 1024,
        fullResDiskBytes: Int = 2 * 1024 * 1024 * 1024
    ) {
        self.memoryBytes = memoryBytes
        self.thumbDiskBytes = thumbDiskBytes
        self.fullResDiskBytes = fullResDiskBytes
    }

    // MARK: - Tenant-size factory

    /// Returns the recommended `ImageCacheSizeConfig` for a given tenant size
    /// hint, per §29.3 ("Tenant-size defaults").
    ///
    /// The user may override `fullResDiskBytes` via Settings after login.
    public static func forTenantSize(_ hint: TenantSizeHint) -> ImageCacheSizeConfig {
        switch hint {
        case .small:
            return ImageCacheSizeConfig(
                memoryBytes:      80 * 1024 * 1024,
                thumbDiskBytes:  500 * 1024 * 1024,
                fullResDiskBytes: 1 * 1024 * 1024 * 1024   // 1 GB
            )
        case .medium:
            return ImageCacheSizeConfig(
                memoryBytes:      80 * 1024 * 1024,
                thumbDiskBytes:  500 * 1024 * 1024,
                fullResDiskBytes: 3 * 1024 * 1024 * 1024   // 3 GB
            )
        case .large:
            return ImageCacheSizeConfig(
                memoryBytes:     120 * 1024 * 1024,
                thumbDiskBytes:  500 * 1024 * 1024,
                fullResDiskBytes: 6 * 1024 * 1024 * 1024   // 6 GB
            )
        case .xlarge:
            return ImageCacheSizeConfig(
                memoryBytes:     160 * 1024 * 1024,
                thumbDiskBytes:  500 * 1024 * 1024,
                fullResDiskBytes: 10 * 1024 * 1024 * 1024  // 10 GB
            )
        }
    }

    // MARK: - Validation

    /// Returns `self` with `fullResDiskBytes` clamped to the §29.3 range
    /// [500 MB … 20 GB].  Use this before persisting a user-supplied value.
    public func clamped() -> ImageCacheSizeConfig {
        var copy = self
        copy.fullResDiskBytes = Swift.max(
            Self.fullResMinBytes,
            Swift.min(Self.fullResMaxBytes, copy.fullResDiskBytes)
        )
        return copy
    }
}
