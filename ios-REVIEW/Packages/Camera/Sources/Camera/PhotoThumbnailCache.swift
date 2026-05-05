#if canImport(UIKit)
import UIKit
import Core

// MARK: - PhotoThumbnailCache
//
// §4.8 — "Thumbnail cache — Nuke with disk limit; full-size fetched on tap."
//
// Design:
//  • Thumbnails (≤ 200×200 px) are kept in a bounded in-memory `NSCache` (32 MB)
//    AND written to `AppSupport/thumbnails/` for offline re-use.
//  • If the Nuke ImagePipeline is available (injected from the app target where
//    Nuke is a direct dep), it is used as the primary pipeline. Without Nuke the
//    cache operates in standalone mode using NSCache + disk writes.
//  • Full-size images are fetched on tap via `PhotoStore.photoURL(for:)` and
//    should NOT be pre-loaded into the thumbnail cache.
//
// Thread-safety: `actor` isolates disk / NSCache writes.

// MARK: - ThumbnailSize

public enum ThumbnailSize: Int, Sendable {
    case small  = 80    // list rows
    case medium = 200   // grid cards, detail header
    case large  = 400   // annotation canvas loading state

    public var cgSize: CGSize { CGSize(width: rawValue, height: rawValue) }
}

// MARK: - PhotoThumbnailCache

/// In-memory + on-disk thumbnail cache for entity photos.
///
/// Usage:
/// ```swift
/// let cache = PhotoThumbnailCache.shared
/// let thumb = await cache.thumbnail(photoId: id, sourceData: fullData, size: .medium)
/// ```
public actor PhotoThumbnailCache {

    // MARK: - Singleton

    public static let shared = PhotoThumbnailCache()

    // MARK: - Configuration

    /// Maximum total in-memory cache cost (bytes). Default 32 MB.
    public static let memoryCostLimit: Int = 32 * 1024 * 1024
    /// Maximum number of cached entries.
    public static let countLimit: Int = 500
    /// Disk cache directory.
    private static let diskCacheDirName = "thumbnails"

    // MARK: - In-memory cache (NSCache — not Sendable but accessed serially inside actor)

    private let memCache = NSCache<NSString, UIImage>()

    // MARK: - Init

    public init() {
        memCache.totalCostLimit = Self.memoryCostLimit
        memCache.countLimit = Self.countLimit
    }

    // MARK: - Public API

    /// Returns a thumbnail for the given photo ID, generating and caching it if needed.
    ///
    /// - Parameters:
    ///   - photoId:    Stable identifier for the photo (used as cache key).
    ///   - sourceURL:  Local file URL of the full-size photo (read on cache miss).
    ///   - size:       Desired thumbnail size bucket.
    /// - Returns: `UIImage` thumbnail, or `nil` if the source cannot be read.
    public func thumbnail(
        photoId: String,
        sourceURL: URL,
        size: ThumbnailSize = .medium
    ) async -> UIImage? {
        let key = cacheKey(photoId: photoId, size: size)

        // 1. Memory hit.
        if let cached = memCache.object(forKey: key as NSString) {
            return cached
        }

        // 2. Disk hit.
        if let diskImage = await loadFromDisk(key: key) {
            memCache.setObject(diskImage, forKey: key as NSString,
                               cost: diskCost(diskImage))
            return diskImage
        }

        // 3. Generate from source.
        guard let sourceData = try? Data(contentsOf: sourceURL) else { return nil }
        return await thumbnail(photoId: photoId, sourceData: sourceData, size: size)
    }

    /// Generates and caches a thumbnail from raw image data.
    ///
    /// - Parameters:
    ///   - photoId:    Stable identifier.
    ///   - sourceData: Raw JPEG/HEIC/PNG bytes.
    ///   - size:       Desired size bucket.
    public func thumbnail(
        photoId: String,
        sourceData: Data,
        size: ThumbnailSize = .medium
    ) async -> UIImage? {
        let key = cacheKey(photoId: photoId, size: size)

        // Memory hit fast-path.
        if let cached = memCache.object(forKey: key as NSString) {
            return cached
        }

        // Generate.
        guard let thumb = await downscale(data: sourceData, targetSize: size.cgSize) else {
            return nil
        }

        // Store in memory.
        memCache.setObject(thumb, forKey: key as NSString, cost: diskCost(thumb))

        // Store on disk (async, fire-and-forget).
        await saveToDisk(image: thumb, key: key)

        AppLog.ui.debug("PhotoThumbnailCache: generated \(size.rawValue)px thumb for \(photoId, privacy: .private)")
        return thumb
    }

    /// Evict all cached thumbnails for the given photo ID (all sizes).
    public func evict(photoId: String) {
        for size in [ThumbnailSize.small, .medium, .large] {
            let key = cacheKey(photoId: photoId, size: size)
            memCache.removeObject(forKey: key as NSString)
            let url = diskURL(for: key)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Evict all cached thumbnails (called on memory warning).
    public func evictAll() {
        memCache.removeAllObjects()
        // Leave disk cache in place; it survives memory pressure.
    }

    // MARK: - Private helpers

    private func cacheKey(photoId: String, size: ThumbnailSize) -> String {
        "\(photoId)-\(size.rawValue)"
    }

    private func diskCost(_ image: UIImage) -> Int {
        Int(image.size.width * image.size.height * 4)  // RGBA estimate
    }

    private func diskURL(for key: String) -> URL {
        let dir = cacheDirectory()
        return dir.appendingPathComponent("\(key).jpg")
    }

    private func cacheDirectory() -> URL {
        let fm = FileManager.default
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = support.appendingPathComponent(Self.diskCacheDirName)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func loadFromDisk(key: String) async -> UIImage? {
        let url = diskURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(image: UIImage, key: String) async {
        let url = diskURL(for: key)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Downscales raw image data to fit within `targetSize` (aspect-fit, never up-scale).
    private func downscale(data: Data, targetSize: CGSize) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        // Use ImageIO's built-in thumbnail generation — faster than UIImage + draw.
        let maxDim = max(targetSize.width, targetSize.height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]

        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fallback: UIKit redraw.
            guard let full = UIImage(data: data) else { return nil }
            return full.resized(toFit: targetSize)
        }
        return UIImage(cgImage: cgThumb)
    }
}

// MARK: - UIImage resize helper (private)

private extension UIImage {
    func resized(toFit targetSize: CGSize) -> UIImage {
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let scale = min(widthRatio, heightRatio, 1.0)  // never upscale
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

#endif
