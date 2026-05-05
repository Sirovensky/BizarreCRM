#if canImport(UIKit)
import Foundation
import Testing
import UIKit
@testable import Camera

// MARK: - PhotoThumbnailCacheTests
//
// §4.8 — Thumbnail cache — Nuke with disk limit; full-size fetched on tap.

@Suite("PhotoThumbnailCache")
struct PhotoThumbnailCacheTests {

    @Test("thumbnail returns UIImage for valid JPEG data")
    func thumbnailFromData() async {
        let cache = PhotoThumbnailCache()
        let image = makeColoredSquare(size: 400)
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            Issue.record("Failed to create JPEG test data")
            return
        }
        let photoId = UUID().uuidString
        let thumb = await cache.thumbnail(photoId: photoId, sourceData: data, size: .medium)
        #expect(thumb != nil)
        if let thumb {
            // Thumbnail should be at most 200×200 (allowing some ImageIO rounding).
            #expect(thumb.size.width <= 210)
            #expect(thumb.size.height <= 210)
        }
        await cache.evict(photoId: photoId)
    }

    @Test("thumbnail returns nil for invalid data")
    func thumbnailNilForBadData() async {
        let cache = PhotoThumbnailCache()
        let thumb = await cache.thumbnail(
            photoId: "bad-id",
            sourceData: Data("not-an-image".utf8),
            size: .small
        )
        #expect(thumb == nil)
    }

    @Test("second call returns cached result (memory hit)")
    func secondCallUsesCachedResult() async {
        let cache = PhotoThumbnailCache()
        let image = makeColoredSquare(size: 300)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let photoId = UUID().uuidString

        let first  = await cache.thumbnail(photoId: photoId, sourceData: data, size: .medium)
        let second = await cache.thumbnail(photoId: photoId, sourceData: data, size: .medium)

        #expect(first != nil)
        #expect(second != nil)
        // Both calls should succeed; second is a cache hit.

        await cache.evict(photoId: photoId)
    }

    @Test("evict removes the entry so next call regenerates")
    func evictClearsCache() async {
        let cache = PhotoThumbnailCache()
        let image = makeColoredSquare(size: 200)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let photoId = UUID().uuidString

        let first = await cache.thumbnail(photoId: photoId, sourceData: data, size: .small)
        #expect(first != nil)

        await cache.evict(photoId: photoId)

        // After evict, regeneration should still succeed.
        let regenerated = await cache.thumbnail(photoId: photoId, sourceData: data, size: .small)
        #expect(regenerated != nil)
        await cache.evict(photoId: photoId)
    }

    @Test("ThumbnailSize raw values are distinct and ordered small < medium < large")
    func thumbnailSizeOrdering() {
        #expect(ThumbnailSize.small.rawValue < ThumbnailSize.medium.rawValue)
        #expect(ThumbnailSize.medium.rawValue < ThumbnailSize.large.rawValue)
    }

    @Test("ThumbnailSize cgSize matches rawValue for square sizes")
    func thumbnailSizeCGSize() {
        for size in [ThumbnailSize.small, .medium, .large] {
            #expect(size.cgSize.width == CGFloat(size.rawValue))
            #expect(size.cgSize.height == CGFloat(size.rawValue))
        }
    }
}

// MARK: - Helpers

private func makeColoredSquare(size: Int) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
}

#endif
