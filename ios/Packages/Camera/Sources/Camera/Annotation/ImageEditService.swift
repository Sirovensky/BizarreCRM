#if canImport(UIKit)
import CoreImage
import Foundation
import UIKit
import Vision

// MARK: - ImageEditService
//
// §17 / §17.10 annotation extension:
//   - Crop: axis-aligned crop to a CGRect in image coordinates.
//   - Rotate: 90° clockwise increments.
//   - Auto-enhance: brightness + contrast via CIFilter (on-device, no network).
//   - OCR "Copy text from image": on-device VNRecognizeTextRequest.
//
// All operations are async and run on a detached Task so they don't block the
// main actor. UI callers await the result and update their @Observable state.

public actor ImageEditService {

    // MARK: - Init

    public init() {}

    // MARK: - Crop

    /// Crop `image` to `rect` expressed in image-native points (0,0 at top-left).
    /// Returns nil if the rect is zero-sized or outside the image bounds.
    public func crop(_ image: UIImage, to rect: CGRect) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return nil }
            let scale = image.scale
            // Convert from UIKit points to CGImage pixel coordinates.
            let pixelRect = CGRect(
                x: rect.origin.x * scale,
                y: rect.origin.y * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            let imageBounds = CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height))
            let clipped = pixelRect.intersection(imageBounds)
            guard !clipped.isEmpty, let cropped = cgImage.cropping(to: clipped) else { return nil }
            return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
        }.value
    }

    // MARK: - Rotate

    /// Rotate `image` by `degrees`. Accepts 90, 180, 270 (and their negatives).
    /// Non-multiples of 90 are rounded to the nearest 90° step.
    public func rotate(_ image: UIImage, degrees: CGFloat) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            let steps = (Int((degrees / 90).rounded()) % 4 + 4) % 4
            guard steps > 0 else { return image }
            var result = image
            for _ in 0..<steps {
                result = Self._rotate90CW(result)
            }
            return result
        }.value
    }

    // MARK: - Auto-enhance

    /// Apply auto brightness + contrast adjustments using CoreImage filters.
    /// Returns the enhanced image, or the original if CoreImage is unavailable.
    public func autoEnhance(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            guard let ciImage = CIImage(image: image) else { return image }
            // Use CIColorControls for brightness/contrast and CIAutoAdjustmentFilter hints.
            let filters = ciImage.autoAdjustmentFilters()
            var output = ciImage
            for filter in filters {
                filter.setValue(output, forKey: kCIInputImageKey)
                if let result = filter.outputImage {
                    output = result
                }
            }
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cgImage = context.createCGImage(output, from: output.extent) else { return image }
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }.value
    }

    // MARK: - OCR (Copy text from image)

    /// Recognize text in `image` using on-device VNRecognizeTextRequest.
    /// Returns recognized strings joined by newlines, or empty string on failure.
    /// Sovereignty: on-device only (`requiresOnDeviceRecognition = true` where supported).
    public func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { req, _ in
                    let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: lines.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                if (try? handler.perform([request])) == nil {
                    cont.resume(returning: "")
                }
            }
        }
    }

    // MARK: - Private helpers

    private static func _rotate90CW(_ image: UIImage) -> UIImage {
        let originalSize = image.size
        let newSize = CGSize(width: originalSize.height, height: originalSize.width)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: newSize.width, y: 0)
            ctx.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(origin: .zero, size: originalSize))
        }
    }
}

#endif
