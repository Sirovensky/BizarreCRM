import SwiftUI

public enum BrandGlassVariant {
    case regular, clear

    fileprivate var fallbackMaterial: Material {
        switch self {
        case .regular: return .ultraThinMaterial
        case .clear:   return .thinMaterial
        }
    }
}

public extension View {
    /// Applies Liquid Glass on iOS 26+, falls back to `.ultraThinMaterial` on 17–25.
    /// Callers should never branch on `#available` themselves — route through this.
    ///
    /// When the project builds against the iOS 26 SDK, extend this modifier
    /// with the real `.glassEffect(...)` call guarded by `#available(iOS 26, *)`.
    /// Kept fallback-only for now so the scaffold builds on Xcode 15 / macos-14.
    func brandGlass<S: Shape>(
        _ variant: BrandGlassVariant = .regular,
        in shape: S,
        tint: Color? = nil
    ) -> some View {
        modifier(BrandGlassModifier(variant: variant, shape: shape, tint: tint))
    }

    /// Capsule-shape convenience (most common: pills, bars, FABs).
    func brandGlass(_ variant: BrandGlassVariant = .regular, tint: Color? = nil) -> some View {
        brandGlass(variant, in: Capsule(), tint: tint)
    }
}

private struct BrandGlassModifier<S: Shape>: ViewModifier {
    let variant: BrandGlassVariant
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background(variant.fallbackMaterial, in: shape)
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(0.15))
                }
            }
    }
}
