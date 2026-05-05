import Foundation

// §29.3 Image loading — Nuke ImagePipeline tuning recommendations.
//
// This file is intentionally free of any `import Nuke` so the Core package
// does not take a hard dependency on the image-pipeline library.  Instead it
// exposes a plain-Swift `NukePipelineOptions` value type that the app layer
// (which already imports Nuke) can apply to `ImagePipeline.Configuration`.
//
// Naming follows Nuke's own API surface so mapping is a one-liner:
//
//   var cfg = ImagePipeline.Configuration.withURLCache
//   NukePipelineOptions.apply(to: &cfg, cache: ImageCacheSizeConfig.forTenantSize(.medium))
//
// The `apply(to:cache:)` helper lives in the app target's bootstrap because it
// needs to import Nuke.  This file provides only the typed constants and docs.

// MARK: - NukePipelineOptions

/// Recommended Nuke `ImagePipeline.Configuration` settings for BizarreCRM per §29.3.
///
/// ## Tuning rationale
///
/// | Setting                        | Value          | Why |
/// |-------------------------------|----------------|-----|
/// | `isProgressiveDecodingEnabled` | `true`         | Renders progressive JPEGs while downloading (§29.3). |
/// | `isStoringPreviewsInMemoryCache`| `true`        | Progressive previews go to memory cache; avoids refetch. |
/// | `isDeduplicationEnabled`       | `true`         | Coalesces concurrent identical-URL fetches (§29.7 dedup). |
/// | `isRateLimiterEnabled`         | `true`         | Prevents burst spike on fast-scroll from saturating the pool. |
/// | `dataCachePolicy`              | `.storeOriginalData` | Full fidelity retained on disk; Nuke re-processes on decode. |
/// | `imageCache` cost limit        | `memoryBytes`  | Per `ImageCacheSizeConfig` (§29.3 80 MB default). |
/// | Thumbnail pipeline disk cap    | `thumbDiskBytes` | Per `ImageCacheSizeConfig` (§29.3 500 MB default). |
/// | Full-res pipeline disk cap     | `fullResDiskBytes` | Per `ImageCacheSizeConfig` (§29.3 2 GB default). |
///
/// ## Two-pipeline architecture
///
/// §29.3 requires a *separate pipeline* for thumbnails vs full-res so that
/// eviction policies can differ (thumbnails are never auto-evicted; full-res
/// uses LRU past the configured cap).
///
/// ```
/// NukePipelineOptions.thumbnailPipelineKey  — shared pipeline name for thumbnail fetches
/// NukePipelineOptions.fullResPipelineKey    — shared pipeline name for full-res fetches
/// ```
///
/// Register both pipelines at app start:
///
/// ```swift
/// // App-layer bootstrap (imports Nuke):
/// func configurePipelines(cache: ImageCacheSizeConfig) {
///     var thumbCfg = ImagePipeline.Configuration.withDataCache(
///         name: NukePipelineOptions.thumbnailDiskCacheName,
///         sizeLimit: cache.thumbDiskBytes
///     )
///     thumbCfg.isProgressiveDecodingEnabled        = NukePipelineOptions.isProgressiveDecodingEnabled
///     thumbCfg.isDeduplicationEnabled              = NukePipelineOptions.isDeduplicationEnabled
///     thumbCfg.isRateLimiterEnabled                = NukePipelineOptions.isRateLimiterEnabled
///
///     var fullCfg = ImagePipeline.Configuration.withDataCache(
///         name: NukePipelineOptions.fullResDiskCacheName,
///         sizeLimit: cache.fullResDiskBytes
///     )
///     fullCfg.isProgressiveDecodingEnabled         = NukePipelineOptions.isProgressiveDecodingEnabled
///     fullCfg.isStoringPreviewsInMemoryCache        = NukePipelineOptions.isStoringPreviewsInMemoryCache
///     fullCfg.isDeduplicationEnabled               = NukePipelineOptions.isDeduplicationEnabled
///     fullCfg.isRateLimiterEnabled                 = NukePipelineOptions.isRateLimiterEnabled
///
///     ImagePipeline.shared = ImagePipeline(configuration: fullCfg)
///     // Store thumbPipeline in a dependency-injected container for thumbnail fetches.
/// }
/// ```
public enum NukePipelineOptions: Sendable {

    // MARK: - Pipeline identity

    /// Disk-cache directory name for the thumbnail pipeline.
    public static let thumbnailDiskCacheName: String  = "com.bizarrecrm.nuke.thumbnails"

    /// Disk-cache directory name for the full-resolution pipeline.
    public static let fullResDiskCacheName: String    = "com.bizarrecrm.nuke.fullres"

    // MARK: - Shared flags

    /// Enable progressive JPEG rendering (§29.3 "Progressive JPEG decode").
    public static let isProgressiveDecodingEnabled: Bool = true

    /// Cache progressive scan previews in the memory layer to avoid re-decode.
    public static let isStoringPreviewsInMemoryCache: Bool = true

    /// Coalesce concurrent fetches of the same URL (§29.7 request deduplication).
    public static let isDeduplicationEnabled: Bool = true

    /// Throttle burst prefetch requests to protect the URLSession pool.
    public static let isRateLimiterEnabled: Bool = true

    // MARK: - Request priority mapping

    /// Priority to use for visible-row image fetches (loaded immediately).
    ///
    /// Maps to `ImageRequest.Priority.high` in Nuke.
    public static let visibleRowPriorityRaw: Int = 4   // Nuke .high

    /// Priority to use for prefetch requests (rows outside the viewport).
    ///
    /// Maps to `ImageRequest.Priority.low` in Nuke.
    public static let prefetchPriorityRaw: Int = 1     // Nuke .low

    // MARK: - Thumbnail URL transform

    /// Appends a `?w=<points>&scale=<scale>` query string so the server
    /// returns a pre-scaled thumbnail instead of the full-resolution image.
    ///
    /// - Parameters:
    ///   - base: The original image URL.
    ///   - widthPts: Requested width in SwiftUI / UIKit points.
    ///   - scale: Screen scale factor (e.g. `UIScreen.main.scale`).
    /// - Returns: URL with `w` and `scale` query parameters added, or `base`
    ///   unchanged if URL components cannot be constructed.
    public static func thumbnailURL(
        for base: URL,
        widthPts: Int,
        scale: CGFloat = 2
    ) -> URL {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == "w" || $0.name == "scale" }
        items.append(URLQueryItem(name: "w",     value: "\(Int(Double(widthPts) * scale))"))
        items.append(URLQueryItem(name: "scale", value: "\(Int(scale))"))
        comps.queryItems = items
        return comps.url ?? base
    }
}
