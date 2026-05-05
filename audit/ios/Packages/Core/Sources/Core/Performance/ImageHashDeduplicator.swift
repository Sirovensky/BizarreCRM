import Foundation
import CryptoKit

// §29.3 Image loading — content-hash deduplication.
//
// Nuke's built-in `isDeduplicationEnabled` dedupes by URL.  That covers the
// common case but misses two scenarios:
//
//   A. The same image is served from multiple CDN URLs (e.g. with different
//      query tokens or regional prefixes).  Nuke fetches it twice.
//
//   B. An upload was processed server-side and re-encoded: the URL changed but
//      the pixel content is identical to a locally-cached version.
//
// `ImageHashDeduplicator` adds a second dedup layer keyed on **content hash**
// (SHA-256 of the raw image bytes).  When a download completes the caller
// registers the (url, hash) pair.  Subsequent requests for any URL mapping to
// the same hash are answered from the in-memory index — no redundant decode.
//
// The deduplicator does NOT cache the image bytes itself; it only tracks the
// mapping from URL → canonical hash and from hash → "already seen" flag.  The
// actual bytes live in Nuke's memory/disk caches.  This keeps the deduplicator
// lightweight and free of Nuke imports.
//
// Usage:
//
//   // After a download completes (in Nuke processor / decode step):
//   ImageHashDeduplicator.shared.register(url: downloadedURL, data: imageData)
//
//   // Before initiating a new fetch:
//   if let canonical = ImageHashDeduplicator.shared.canonicalURL(for: candidateURL) {
//       // Use `canonical` URL to hit the already-cached pipeline entry instead.
//   }

/// Content-hash-based deduplicator for image fetches per §29.3.
///
/// Thread-safe via an internal `NSLock`.  All methods may be called from any
/// thread or actor.
public final class ImageHashDeduplicator: @unchecked Sendable {

    // MARK: - Shared instance

    public static let shared = ImageHashDeduplicator()

    // MARK: - State

    private let lock = NSLock()

    /// url.absoluteString → SHA-256 hex string
    private nonisolated(unsafe) var _urlToHash: [String: String] = [:]

    /// SHA-256 hex string → canonical (first-seen) URL string
    private nonisolated(unsafe) var _hashToCanonicalURL: [String: String] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Registers a downloaded image's content hash.
    ///
    /// Call this once after a successful image download — typically in a Nuke
    /// `ImageProcessing` step or a post-download hook.
    ///
    /// - Parameters:
    ///   - url: The URL the image was fetched from.
    ///   - data: The raw image bytes (used to compute SHA-256).
    public func register(url: URL, data: Data) {
        let hash = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        let key = url.absoluteString

        lock.lock()
        defer { lock.unlock() }

        _urlToHash[key] = hash

        // First registration for this hash wins as the canonical URL.
        if _hashToCanonicalURL[hash] == nil {
            _hashToCanonicalURL[hash] = key
        }
    }

    /// Returns the canonical URL for `url` if its content has already been
    /// downloaded under a different URL, or `nil` if no dedup match is found.
    ///
    /// When a non-nil URL is returned the caller should use it as the request
    /// URL so that Nuke's URL-keyed disk/memory caches serve the existing entry.
    ///
    /// - Parameter url: Candidate URL for a new image fetch.
    /// - Returns: The canonical URL already in cache, or `nil`.
    public func canonicalURL(for url: URL) -> URL? {
        let key = url.absoluteString

        lock.lock()
        defer { lock.unlock() }

        // If this URL is already the canonical one, no redirect needed.
        guard let hash = _urlToHash[key] else { return nil }
        guard let canonical = _hashToCanonicalURL[hash] else { return nil }
        guard canonical != key else { return nil }

        return URL(string: canonical)
    }

    /// Returns `true` when the content at `url` has already been downloaded.
    ///
    /// Useful as a fast pre-flight check before creating a new Nuke request.
    ///
    /// - Parameter url: URL to check.
    public func isKnown(url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _urlToHash[url.absoluteString] != nil
    }

    /// Returns the SHA-256 hex string for the content at `url`, or `nil` if
    /// it has not been registered yet.
    ///
    /// - Parameter url: URL to look up.
    public func contentHash(for url: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return _urlToHash[url.absoluteString]
    }

    /// Removes all URL→hash and hash→canonical mappings.
    ///
    /// Call on `applicationDidReceiveMemoryWarning` or when the tenant session
    /// changes to avoid serving stale cross-tenant mappings.
    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        _urlToHash.removeAll(keepingCapacity: true)
        _hashToCanonicalURL.removeAll(keepingCapacity: true)
    }

    /// Removes the mapping for a specific URL (e.g. after a 404).
    ///
    /// - Parameter url: The URL whose registration should be purged.
    public func invalidate(url: URL) {
        let key = url.absoluteString

        lock.lock()
        defer { lock.unlock() }

        if let hash = _urlToHash.removeValue(forKey: key) {
            // If this was the canonical URL for its hash, remove that too so
            // the next registration for the same content wins the canonical slot.
            if _hashToCanonicalURL[hash] == key {
                _hashToCanonicalURL.removeValue(forKey: hash)
            }
        }
    }
}
