#if canImport(SwiftUI)
import SwiftUI

// MARK: - BarcodePreviewChip
//
// §17: "Preview layer marks detected code with glass chip + content preview;
//       tap chip to accept"
//
// Shown as an overlay on the live camera preview when a barcode is detected
// but not yet accepted. The chip shows the barcode value, a mini content
// preview (item name if lookup resolves), and a tap-to-accept CTA.
//
// Liquid Glass style: chrome element (not content), so `.ultraThinMaterial`
// is correct per the ios/CLAUDE.md rules.

/// A glass chip displayed over a camera preview when a barcode is detected.
///
/// Usage (inside a ZStack over the camera view):
/// ```swift
/// BarcodePreviewChip(
///     barcode: detectedBarcode,
///     lookupResult: lookupResult,
///     onAccept: { acceptBarcode(detectedBarcode) },
///     onDismiss: { detectedBarcode = nil }
/// )
/// ```
public struct BarcodePreviewChip: View {

    public let barcode: Barcode
    /// Resolved item from inventory lookup; `nil` while pending or if not found.
    public let lookupResult: BarcodeLookupResult?
    public let onAccept: () -> Void
    public let onDismiss: () -> Void

    public init(
        barcode: Barcode,
        lookupResult: BarcodeLookupResult?,
        onAccept: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.barcode = barcode
        self.lookupResult = lookupResult
        self.onAccept = onAccept
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Barcode icon
            Image(systemName: "barcode.viewfinder")
                .font(.title3)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let item = lookupResult {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(barcode.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let price = item.retailPrice {
                            Text(String(format: "$%.2f", price))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                    }
                } else {
                    Text(barcode.value)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(barcode.symbology.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Accept button
            Button(action: onAccept) {
                Text("Add")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.tint, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Accept scanned barcode \(barcode.value)")

            // Dismiss
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss barcode chip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chipAccessibilityLabel)
        .accessibilityHint("Double-tap to accept the scanned item")
    }

    private var chipAccessibilityLabel: String {
        if let item = lookupResult {
            return "Scanned: \(item.displayName). Code: \(barcode.value)."
        }
        return "Scanned barcode: \(barcode.value). Symbology: \(barcode.symbology)."
    }
}
#endif
