import Foundation
import UIKit

// §4.8 Thumbnail cache — disk-limited cache for ticket photo thumbnails.
//
// Uses URLCache with a 50 MB disk limit and 5 MB memory limit.
// Full-size photos are fetched on tap (not cached here — too large).
// The singleton is shared across all TicketDevicePhotoListView instances.
//
// Usage:
//   let cache = TicketThumbnailCache.shared
//   if let data = await cache.data(for: url) { ... }
//   cache.store(data: data, for: url)

public actor TicketThumbnailCache {

    // MARK: - Singleton

    public static let shared = TicketThumbnailCache()

    // MARK: - Constants

    /// Disk limit: 50 MB (thumbnails are small; full-size fetched on demand).
    private static let diskCapacity = 50 * 1024 * 1024
    /// Memory limit: 5 MB.
    private static let memoryCapacity = 5 * 1024 * 1024

    // MARK: - Storage

    private let cache: URLCache

    // MARK: - Init

    private init() {
        cache = URLCache(
            memoryCapacity: Self.memoryCapacity,
            diskCapacity: Self.diskCapacity,
            directory: Self.cacheDirectory()
        )
    }

    // MARK: - Public API

    /// Returns cached thumbnail data for `url`, or nil if not cached.
    public func data(for url: URL) -> Data? {
        let request = URLRequest(url: url)
        return cache.cachedResponse(for: request)?.data
    }

    /// Stores `data` in the cache keyed by `url`.
    public func store(data: Data, for url: URL) {
        let request = URLRequest(url: url)
        // URLCache requires a valid HTTPURLResponse to store entries.
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/jpeg"]
        ) else { return }
        let cached = CachedURLResponse(response: response, data: data)
        cache.storeCachedResponse(cached, for: request)
    }

    /// Evicts all cached thumbnails. Called from Settings → Clear Cache.
    public func removeAll() {
        cache.removeAllCachedResponses()
    }

    /// Current disk usage in bytes.
    public var currentDiskUsage: Int {
        cache.currentDiskUsage
    }

    // MARK: - Private helpers

    private static func cacheDirectory() -> URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TicketThumbnails", isDirectory: true)
    }
}

// MARK: - AsyncImageLoader

/// Fetches a remote URL with thumbnail cache support.
/// Uses `TicketThumbnailCache` for disk caching; falls back to live download.
///
/// Returns a `UIImage` or nil if the download fails.
public actor AsyncThumbnailLoader {

    public static func load(url: URL) async -> UIImage? {
        let cache = TicketThumbnailCache.shared

        // Cache hit
        if let data = await cache.data(for: url),
           let image = UIImage(data: data) {
            return image
        }

        // Cache miss — download
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            // Downsample to thumbnail size before caching (saves disk space)
            let thumb = downsample(image: image, to: CGSize(width: 320, height: 320))
            let thumbData = thumb.jpegData(compressionQuality: 0.75) ?? data
            await cache.store(data: thumbData, for: url)
            return thumb
        } catch {
            return nil
        }
    }

    // MARK: - Downsampling

    private static func downsample(image: UIImage, to targetSize: CGSize) -> UIImage {
        let scale = min(
            targetSize.width  / image.size.width,
            targetSize.height / image.size.height,
            1.0   // never upscale
        )
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
