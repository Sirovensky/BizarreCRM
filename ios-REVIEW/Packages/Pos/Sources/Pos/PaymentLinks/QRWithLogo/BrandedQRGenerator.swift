import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §41.6 Branded QR generator

/// Generates a QR code image with the tenant logo centered.
/// Uses `CoreImage` CIQRCodeGenerator (error-correction level H — tolerates
/// ~30 % module damage, required for logo overlay). Compositing is pure
/// CoreGraphics and is free of UIKit dependencies so logic can run in tests
/// or in background isolations.
///
/// All methods are `nonisolated` and `Sendable`-safe.
public enum BrandedQRGenerator {

    /// Generate a QR code for `urlString` at `size` × `size` points.
    /// Returns `nil` only when CoreImage is unavailable or the string is empty.
    ///
    /// - Parameters:
    ///   - urlString:  The URL to encode. Must be non-empty.
    ///   - size:       Output image side length in points (default 300).
    ///   - logo:       Optional logo UIImage overlaid in the center (25 % of size).
    ///   - foreground: QR module color (default .black).
    ///   - background: QR background color (default .white).
    ///
    /// - Returns: A `UIImage` on success, `nil` on failure.
#if canImport(UIKit)
    public static func generate(
        urlString: String,
        size: CGFloat = 300,
        logo: UIImage? = nil,
        foreground: UIColor = .black,
        background: UIColor = .white
    ) -> UIImage? {
        guard !urlString.isEmpty else { return nil }

        // 1. Generate the base QR bitmap via CoreImage.
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.correctionLevel = "H"   // level H — tolerates ~30 % damage
        guard let data = urlString.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")

        guard let output = filter.outputImage else { return nil }

        // 2. Scale up to requested size (nearest-neighbour — keeps crisp edges).
        let scaleX = size / output.extent.width
        let scaleY = size / output.extent.height
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // 3. Apply foreground + background tint via color controls.
        guard let tinted = tint(image: scaled, foreground: foreground, background: background) else {
            return nil
        }

        // 4. Render to CGImage.
        guard let cgImage = context.createCGImage(tinted, from: tinted.extent) else { return nil }

        // 5. Composite logo if provided.
        if let logo {
            return composite(qr: cgImage, logo: logo, size: size)
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Private helpers

    private static func tint(
        image: CIImage,
        foreground: UIColor,
        background: UIColor
    ) -> CIImage? {
        // Map: black modules → foreground, white background → background.
        let fgCI = CIColor(color: foreground)
        let bgCI = CIColor(color: background)

        let colorFilter = CIFilter.falseColor()
        colorFilter.setValue(image, forKey: kCIInputImageKey)
        colorFilter.setValue(fgCI, forKey: "inputColor0")
        colorFilter.setValue(bgCI, forKey: "inputColor1")
        return colorFilter.outputImage
    }

    private static func composite(qr: CGImage, logo: UIImage, size: CGFloat) -> UIImage? {
        let logoSide = size * 0.25
        let logoRect = CGRect(
            x: (size - logoSide) / 2,
            y: (size - logoSide) / 2,
            width: logoSide,
            height: logoSide
        )
        // White backing circle behind logo for readability.
        let padding: CGFloat = 4
        let circleRect = logoRect.insetBy(dx: -padding, dy: -padding)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            // Flip coordinate system (CoreGraphics origin is bottom-left).
            cgCtx.translateBy(x: 0, y: size)
            cgCtx.scaleBy(x: 1, y: -1)
            cgCtx.draw(qr, in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            // Flip back for UIKit drawing.
            cgCtx.translateBy(x: 0, y: size)
            cgCtx.scaleBy(x: 1, y: -1)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: circleRect).fill()
            logo.draw(in: logoRect)
        }
    }
#endif
}
