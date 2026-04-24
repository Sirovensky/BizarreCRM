import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreLocation

// MARK: - Result type

public struct ExifStrippedImage: Sendable {
    /// JPEG data with GPS and timestamp metadata removed.
    public let jpegData: Data
    /// Keys that were stripped from the original metadata.
    public let strippedKeys: [String]
}

// MARK: - Error

public enum ExifStripError: LocalizedError, Sendable {
    case invalidImageData
    case cgImageSourceCreationFailed
    case cgImageSourceCopyFailed
    case destinationCreationFailed
    case destinationFinalizationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImageData:               return "The provided data is not a valid image."
        case .cgImageSourceCreationFailed:    return "Could not read image source."
        case .cgImageSourceCopyFailed:        return "Could not read image properties."
        case .destinationCreationFailed:      return "Could not create image destination."
        case .destinationFinalizationFailed:  return "Could not write stripped image."
        }
    }
}

// MARK: - Stripper

/// Pure function that strips GPS location data and timestamp from JPEG/HEIC
/// image metadata using ImageIO. Returns a new JPEG with the sensitive keys
/// removed; the original data is never mutated.
///
/// Keys stripped:
///   - `{GPS}` dictionary (all sub-keys: latitude, longitude, altitude, etc.)
///   - `{Exif}.DateTimeOriginal`, `DateTimeDigitized`, `OffsetTime*`
///   - `{TIFF}.DateTime`
///   - `{IPTC}.DateCreated`, `TimeCreated`
public enum ExifStripper {

    // Keys to strip from the top-level metadata dictionary.
    private static let topLevelKeysToRemove: Set<String> = [
        kCGImagePropertyGPSDictionary as String
    ]

    // Sub-keys to strip from the Exif sub-dictionary.
    private static let exifKeysToRemove: Set<String> = [
        kCGImagePropertyExifDateTimeOriginal as String,
        kCGImagePropertyExifDateTimeDigitized as String,
        "OffsetTime",
        "OffsetTimeOriginal",
        "OffsetTimeDigitized"
    ]

    // Sub-keys to strip from the TIFF sub-dictionary.
    private static let tiffKeysToRemove: Set<String> = [
        kCGImagePropertyTIFFDateTime as String
    ]

    // Sub-keys to strip from the IPTC sub-dictionary.
    private static let iptcKeysToRemove: Set<String> = [
        kCGImagePropertyIPTCDateCreated as String,
        kCGImagePropertyIPTCTimeCreated as String
    ]

    // MARK: - Public API

    /// Strips location and timestamp metadata from the supplied image data.
    /// Input may be JPEG or HEIC; output is always JPEG.
    ///
    /// - Parameter data: Raw image bytes (JPEG or HEIC).
    /// - Returns: `ExifStrippedImage` with cleaned JPEG data and a list of
    ///   stripped key names, or throws `ExifStripError` on failure.
    public static func strip(from data: Data) throws -> ExifStrippedImage {
        guard !data.isEmpty else { throw ExifStripError.invalidImageData }

        // Create source
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            throw ExifStripError.cgImageSourceCreationFailed
        }

        // Read original properties
        guard let originalProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw ExifStripError.cgImageSourceCopyFailed
        }

        // Build cleaned metadata and track stripped keys
        let (cleanedProps, strippedKeys) = buildCleanedProperties(from: originalProps)

        // Create JPEG destination
        let outputBuffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputBuffer,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ExifStripError.destinationCreationFailed
        }

        // Add image with stripped metadata
        CGImageDestinationAddImageFromSource(
            destination,
            source,
            0,
            cleanedProps as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw ExifStripError.destinationFinalizationFailed
        }

        return ExifStrippedImage(
            jpegData: outputBuffer as Data,
            strippedKeys: strippedKeys
        )
    }

    // MARK: - Private helpers

    private static func buildCleanedProperties(
        from original: [String: Any]
    ) -> (cleaned: [String: Any], stripped: [String]) {
        var cleaned = original
        var stripped: [String] = []

        // Remove top-level GPS dictionary
        for key in topLevelKeysToRemove {
            if cleaned.removeValue(forKey: key) != nil {
                stripped.append(key)
            }
        }

        // Strip from Exif sub-dictionary
        if var exif = cleaned[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            for key in exifKeysToRemove where exif[key] != nil {
                exif.removeValue(forKey: key)
                stripped.append("Exif.\(key)")
            }
            cleaned[kCGImagePropertyExifDictionary as String] = exif
        }

        // Strip from TIFF sub-dictionary
        if var tiff = cleaned[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            for key in tiffKeysToRemove where tiff[key] != nil {
                tiff.removeValue(forKey: key)
                stripped.append("TIFF.\(key)")
            }
            cleaned[kCGImagePropertyTIFFDictionary as String] = tiff
        }

        // Strip from IPTC sub-dictionary
        if var iptc = cleaned[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
            for key in iptcKeysToRemove where iptc[key] != nil {
                iptc.removeValue(forKey: key)
                stripped.append("IPTC.\(key)")
            }
            cleaned[kCGImagePropertyIPTCDictionary as String] = iptc
        }

        return (cleaned, stripped)
    }
}
