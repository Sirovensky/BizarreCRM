#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import SwiftUI
import UIKit

// MARK: - AnnotationStamp
//
// §17.10 (Annotation tools group):
//   "Stamp library: Arrow / Star / circled number / condition tags ('cracked', 'dented', 'missing');
//    drag-drop onto image."
//   "Layers: base photo + annotation layer stored separately (revert-to-original possible);
//    export flattens."
//
// Additional tools extended in AnnotationTool.swift are declared here in a
// companion file to avoid swelling that file. Extended tools (arrow, rectangle,
// oval, text box) are added as a Swift extension on AnnotationTool.

// MARK: - Stamp catalog

/// Pre-built stamp shapes available in the annotation tool palette.
///
/// Each stamp renders as a vector path drawn with `UIBezierPath` into an
/// `UIImage`, then placed as a `PKStroke`-equivalent overlay (drawn into a
/// separate `UIGraphicsImageRenderer` layer before flattening).
public enum AnnotationStamp: String, CaseIterable, Sendable, Identifiable {

    // MARK: - Cases

    case arrow
    case star
    case circledOne
    case circledTwo
    case circledThree
    case circledFour
    case circledFive
    case tagCracked
    case tagDented
    case tagMissing
    case tagWorking
    case tagFaulty

    public var id: String { rawValue }

    // MARK: - Display

    public var label: String {
        switch self {
        case .arrow:       return "Arrow"
        case .star:        return "Star"
        case .circledOne:  return "①"
        case .circledTwo:  return "②"
        case .circledThree: return "③"
        case .circledFour: return "④"
        case .circledFive: return "⑤"
        case .tagCracked:  return "Cracked"
        case .tagDented:   return "Dented"
        case .tagMissing:  return "Missing"
        case .tagWorking:  return "Working"
        case .tagFaulty:   return "Faulty"
        }
    }

    public var systemImageName: String {
        switch self {
        case .arrow:         return "arrow.up.right"
        case .star:          return "star.fill"
        case .circledOne:    return "1.circle.fill"
        case .circledTwo:    return "2.circle.fill"
        case .circledThree:  return "3.circle.fill"
        case .circledFour:   return "4.circle.fill"
        case .circledFive:   return "5.circle.fill"
        case .tagCracked:    return "exclamationmark.triangle.fill"
        case .tagDented:     return "minus.circle.fill"
        case .tagMissing:    return "questionmark.circle.fill"
        case .tagWorking:    return "checkmark.circle.fill"
        case .tagFaulty:     return "xmark.circle.fill"
        }
    }

    /// Condition-tag stamps shown in the "Condition" section of the palette.
    public static var conditionTags: [AnnotationStamp] {
        [.tagCracked, .tagDented, .tagMissing, .tagWorking, .tagFaulty]
    }

    /// Number stamps (circled digits).
    public static var numbered: [AnnotationStamp] {
        [.circledOne, .circledTwo, .circledThree, .circledFour, .circledFive]
    }

    // MARK: - Rendering

    /// Renders the stamp as a 64×64 `UIImage` at the given tint colour.
    public func image(tintColor: UIColor = .systemOrange) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        let symbol = UIImage(systemName: systemImageName, withConfiguration: config)?
            .withTintColor(tintColor, renderingMode: .alwaysOriginal)
        ?? UIImage(systemName: "questionmark.circle.fill")?
            .withTintColor(tintColor, renderingMode: .alwaysOriginal)
        ?? UIImage()
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            symbol.draw(in: rect)
        }
    }
}

// MARK: - AnnotationLayer

/// Models the two-layer approach for photo annotation:
///  - `baseImage`:      the original photo (read-only; never mutated)
///  - `annotationData`: the PKDrawing serialised for later editing or revert
///  - `stamps`:         any placed `AnnotationStampPlacement` objects
///
/// §17: "Layers: base photo + annotation layer stored separately
///       (revert-to-original possible); export flattens."
public struct AnnotationLayer: Sendable, Codable {

    // MARK: - Base image (stored as JPEG data for Codable)

    /// JPEG representation of the base photo.
    public let baseImageData: Data

    /// PencilKit drawing bytes (`PKDrawing.dataRepresentation()`).
    public var drawingData: Data

    /// Placed stamps (position + type + tint colour).
    public var stamps: [AnnotationStampPlacement]

    // MARK: - Init

    public init(baseImageData: Data, drawingData: Data = Data(), stamps: [AnnotationStampPlacement] = []) {
        self.baseImageData = baseImageData
        self.drawingData = drawingData
        self.stamps = stamps
    }

    // MARK: - Revert

    /// Returns a copy with only the base image (no drawing or stamps).
    public func revertedToOriginal() -> AnnotationLayer {
        AnnotationLayer(baseImageData: baseImageData)
    }
}

// MARK: - AnnotationStampPlacement

/// A concrete instance of a stamp placed on the canvas.
public struct AnnotationStampPlacement: Identifiable, Codable, Sendable {
    public var id: UUID
    public var stamp: AnnotationStamp
    /// Normalised position (0…1 in both axes).
    public var normalizedX: Double
    public var normalizedY: Double
    /// Size in points on the canvas.
    public var size: Double
    /// Hex-encoded tint colour string.
    public var tintHex: String

    public init(
        id: UUID = UUID(),
        stamp: AnnotationStamp,
        normalizedX: Double,
        normalizedY: Double,
        size: Double = 64,
        tintHex: String = "#FF7A00"
    ) {
        self.id = id
        self.stamp = stamp
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.size = size
        self.tintHex = tintHex
    }
}

// MARK: - AnnotationStamp Codable

extension AnnotationStamp: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = AnnotationStamp(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown AnnotationStamp: \(raw)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
#endif
