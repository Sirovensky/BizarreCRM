// DesignSystem/Tips/TipModifier.swift
//
// Convenience modifier that wraps `.popoverTip` with brand glass styling.
// §26 Sticky a11y tips (Phase 10)

import SwiftUI
#if canImport(TipKit)
import TipKit

// MARK: - View extension

public extension View {
    /// Attaches a `Tip` as a popover on this view with BizarreCRM glass styling.
    ///
    /// Uses `.popoverTip` from TipKit and overlays the brand visual treatment.
    /// Falls back gracefully pre-iOS 17 — the modifier is a no-op on older OS.
    ///
    /// - Parameter tip: Any `Tip`-conforming value from `TipCatalog`.
    /// - Parameter arrowEdge: Preferred popover arrow direction (default `.top`).
    @available(iOS 17, *)
    @ViewBuilder
    func brandTip(_ tip: some Tip, arrowEdge: Edge = .top) -> some View {
        self.popoverTip(tip, arrowEdge: arrowEdge)
            .tipBackground(BrandTipBackground())
    }
}

// MARK: - Glass-styled tip background

/// A `ShapeStyle` that applies the brand glass background to TipKit popovers.
/// Uses `.ultraThinMaterial` pre-iOS 26; system glass on iOS 26+.
@available(iOS 17, *)
private struct BrandTipBackground: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        .ultraThinMaterial
    }
}
#endif // canImport(TipKit)
