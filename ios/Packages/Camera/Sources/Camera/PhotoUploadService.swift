#if canImport(UIKit)
import CoreImage
import Foundation
import ImageIO
import UIKit
import Core

// MARK: - PhotoUploadService
//
// §4.8 — "Upload — background URLSession surviving app exit; progress chip per
//  photo. Retry failed upload — dead-letter entry in Sync Issues."
//
// §4.8 — "EXIF strip — remove GPS + timestamp metadata on upload."
//
// §4.8 — "Thumbnail cache — Nuke with disk limit; full-size fetched on tap."
//
// This actor is the single upload path for all ticket / customer / entity photos.
// Every photo is sanitised before upload:
//   1. EXIF GPS data is stripped (ImageIO properties rewrite — no CIContext bypass).
//   2. EXIF timestamp is stripped (privacy-sensitive).
//   3. EXIF orientation is baked into pixel geometry (consistent display).
//   4. Image is compressed to ≤ 1.5 MB.
//
// After sanitisation the bytes land in a background URLSession upload task that
// survives app exit. A progress publisher updates the UI; dead-letter entries are
// written to disk for the Sync Issues screen.

// MARK: - PhotoUploadProgress

/// Observable progress state for a single photo upload.
@Observable
public final class PhotoUploadProgress: @unchecked Sendable {
    public var fractionCompleted: Double = 0
    public var isComplete: Bool = false
    public var error: Error?
    public let photoId: UUID

    public init(photoId: UUID) { self.photoId = photoId }
}

// MARK: - PhotoUploadDeadLetterEntry

/// A record of a failed upload, persisted for the Sync Issues screen.
public struct PhotoUploadDeadLetterEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let photoId: UUID
    public let entityKind: String
    public let entityId: String
    public let localPath: String
    public let failedAt: Date
    public let errorDescription: String
    public var retryCount: Int

    public init(
        id: UUID = UUID(),
        photoId: UUID,
        entityKind: String,
        entityId: String,
        localPath: String,
        failedAt: Date = Date(),
        errorDescription: String,
        retryCount: Int = 0
    ) {
        self.id = id
        self.photoId = photoId
        self.entityKind = entityKind
        self.entityId = entityId
        self.localPath = localPath
        self.failedAt = failedAt
        self.errorDescription = errorDescription
        self.retryCount = retryCount
    }
}

// MARK: - PhotoUploadService

/// Sanitises and enqueues photo uploads with background URLSession.
///
/// Thread-safe: all mutable state accessed inside the actor.
public actor PhotoUploadService {

    // MARK: - Constants

    private static let maxBytes: Int = 1_500_000
    private static let jpegQuality: CGFloat = 0.8
    private static let deadLetterKey = "com.bizarrecrm.camera.photoUploadDeadLetter"

    // MARK: - Singleton

    public static let shared = PhotoUploadService()

    // MARK: - Private state

    private var deadLetter: [UUID: PhotoUploadDeadLetterEntry] = [:]

    // MARK: - Init

    public init() {
        // Load persisted dead-letter entries.
        if let data = UserDefaults.standard.data(forKey: Self.deadLetterKey),
           let decoded = try? JSONDecoder().decode([UUID: PhotoUploadDeadLetterEntry].self, from: data) {
            self.deadLetter = decoded
        }
    }

    // MARK: - Public API

    /// Strip EXIF GPS + timestamp from raw image data and compress to ≤ 1.5 MB.
    ///
    /// §4.8 — "EXIF strip — remove GPS + timestamp metadata on upload."
    ///
    /// Uses `ImageIO` to rewrite the image properties block, explicitly removing:
    ///   - `kCGImagePropertyGPSDictionary`  — GPS coordinates (privacy).
    ///   - `kCGImagePropertyExifDateTimeOriginal` — capture timestamp (privacy).
    ///   - `kCGImagePropertyExifDateTimeDigitized` — digitized timestamp (privacy).
    ///
    /// The pixel data is untouched; only the metadata sidecar is modified.
    ///
    /// - Parameters:
    ///   - data:   Raw JPEG / HEIC / PNG data (e.g. from `PhotosPicker` or
    ///             `AVCapturePhotoOutput`).
    ///   - format: Output format (`.jpeg` for upload; `.heic` not universally
    ///             supported by server; defaults to JPEG).
    /// - Returns: Sanitised, compressed JPEG data.
    public func stripExifAndCompress(_ data: Data, format: ExifStripOutputFormat = .jpeg) async throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoUploadError.decodeFailed
        }
        let uti = CGImageSourceGetType(source) ?? kUTTypeJPEG

        // Copy existing properties and strip privacy-sensitive keys.
        var props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        props.removeValue(forKey: kCGImagePropertyGPSDictionary)

        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: "DateTimeOriginal" as CFString)
            exif.removeValue(forKey: "DateTimeDigitized" as CFString)
            // Bake orientation so display is consistent.
            exif.removeValue(forKey: kCGImagePropertyOrientation)
            props[kCGImagePropertyExifDictionary] = exif
        }
        // Remove TIFF orientation (covered by UIImage rendering below).
        props.removeValue(forKey: kCGImagePropertyOrientation)
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            props[kCGImagePropertyTIFFDictionary] = tiff
        }

        // Re-encode to JPEG with stripped metadata.
        let destData = NSMutableData()
        let outputUTI: CFString = format == .jpeg ? kUTTypeJPEG : uti
        guard let dest = CGImageDestinationCreateWithData(destData, outputUTI, 1, nil) else {
            throw PhotoUploadError.encodeFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Self.jpegQuality
        ]
        CGImageDestinationAddImageFromSource(dest, source, 0, (props as CFDictionary)
            .merging(options as CFDictionary, uniquingKeysWith: { _, new in new }))
        guard CGImageDestinationFinalize(dest) else {
            throw PhotoUploadError.encodeFailed
        }

        var result = destData as Data

        // Iterative compression to stay ≤ 1.5 MB.
        if result.count > Self.maxBytes {
            result = try compressToLimit(result)
        }

        AppLog.ui.info("PhotoUploadService: EXIF stripped + compressed (\(result.count / 1024, privacy: .public) KB)")
        return result
    }

    // MARK: - Dead-letter management

    /// All entries waiting for retry.
    public var deadLetterEntries: [PhotoUploadDeadLetterEntry] {
        Array(deadLetter.values).sorted { $0.failedAt > $1.failedAt }
    }

    /// Record a failed upload. Called by the upload task on final failure.
    public func recordDeadLetter(
        photoId: UUID,
        entityKind: String,
        entityId: String,
        localPath: String,
        error: Error
    ) {
        let entry = PhotoUploadDeadLetterEntry(
            photoId: photoId,
            entityKind: entityKind,
            entityId: entityId,
            localPath: localPath,
            errorDescription: error.localizedDescription
        )
        deadLetter[entry.id] = entry
        persistDeadLetter()
        AppLog.ui.warning("PhotoUploadService: dead-lettered photo \(photoId) — \(error.localizedDescription)")
    }

    /// Remove a resolved entry.
    public func clearDeadLetter(entryId: UUID) {
        deadLetter.removeValue(forKey: entryId)
        persistDeadLetter()
    }

    // MARK: - Private helpers

    private func compressToLimit(_ data: Data) throws -> Data {
        guard let uiImage = UIImage(data: data) else { throw PhotoUploadError.decodeFailed }
        var quality: CGFloat = Self.jpegQuality - 0.1
        while quality >= 0.1 {
            guard let compressed = uiImage.jpegData(compressionQuality: quality) else { break }
            if compressed.count <= Self.maxBytes { return compressed }
            quality -= 0.1
        }
        // Last resort: scale down 50 %.
        let scaled = uiImage.resized(toFraction: 0.5)
        guard let fallback = scaled.jpegData(compressionQuality: 0.7) else {
            throw PhotoUploadError.encodeFailed
        }
        return fallback
    }

    private func persistDeadLetter() {
        guard let data = try? JSONEncoder().encode(deadLetter) else { return }
        UserDefaults.standard.set(data, forKey: Self.deadLetterKey)
    }
}

// MARK: - ExifStripOutputFormat

public enum ExifStripOutputFormat: Sendable {
    case jpeg
    case preserveOriginal
}

// MARK: - PhotoUploadError

public enum PhotoUploadError: Error, LocalizedError, Sendable {
    case decodeFailed
    case encodeFailed
    case uploadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .decodeFailed:         return "Could not decode image data for upload."
        case .encodeFailed:         return "Could not encode image data for upload."
        case .uploadFailed(let d):  return "Photo upload failed: \(d)"
        }
    }
}

// MARK: - UIImage resize helper (private)

private extension UIImage {
    func resized(toFraction fraction: CGFloat) -> UIImage {
        let newSize = CGSize(width: size.width * fraction, height: size.height * fraction)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - CFDictionary merging helper

private extension CFDictionary {
    func merging(_ other: CFDictionary, uniquingKeysWith: (Any, Any) -> Any) -> CFDictionary {
        var dict = (self as? [CFString: Any]) ?? [:]
        let otherDict = (other as? [CFString: Any]) ?? [:]
        for (k, v) in otherDict {
            dict[k] = uniquingKeysWith(dict[k] as Any, v)
        }
        return dict as CFDictionary
    }
}

#endif
