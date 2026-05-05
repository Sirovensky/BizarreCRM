import SwiftUI

// MARK: - §80 Bold Text environment gate
//
// Gate on `@Environment(\.legibilityWeight) == .bold` to reflect the iOS
// "Bold Text" system accessibility setting.  When active, bump text weights
// by one step so legibility is preserved even on body / callout styles.
//
// Default = regular weight per §80 / §80 typography table.
//
// Usage:
//   @Environment(\.boldTextEnabled) private var boldTextEnabled
//   Text("Hello")
//       .fontWeight(boldTextEnabled ? .semibold : .regular)
//
// Or use the convenience modifier:
//   Text("Hello").adaptiveFontWeight(.regular)  // → semibold when Bold Text on

// MARK: - EnvironmentKey

private struct BoldTextEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// `true` when the user has enabled "Bold Text" in iOS Accessibility settings.
    ///
    /// Reads `\.legibilityWeight` from the environment; bridged to a `Bool`
    /// for ergonomic consumption.
    public var boldTextEnabled: Bool {
        get { self[BoldTextEnabledKey.self] }
        set { self[BoldTextEnabledKey.self] = newValue }
    }
}

// MARK: - BoldTextReader modifier

extension View {
    /// Reads `legibilityWeight` from the environment and writes `boldTextEnabled`
    /// into it for downstream consumers.
    ///
    /// Apply once at the scene root:
    ///   MainShellView().boldTextReader()
    public func boldTextReader() -> some View {
        self.modifier(BoldTextReaderModifier())
    }
}

private struct BoldTextReaderModifier: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        content
            .environment(\.boldTextEnabled, legibilityWeight == .bold)
    }
}

// MARK: - Convenience modifier

extension View {
    /// Apply a font weight that escalates one step when Bold Text is enabled.
    ///
    ///   Text("Revenue").adaptiveFontWeight(.regular)
    ///   // → .regular normally, .semibold when Bold Text is on.
    public func adaptiveFontWeight(_ base: Font.Weight) -> some View {
        self.modifier(AdaptiveFontWeightModifier(base: base))
    }
}

private struct AdaptiveFontWeightModifier: ViewModifier {
    let base: Font.Weight
    @Environment(\.boldTextEnabled) private var boldTextEnabled

    func body(content: Content) -> some View {
        content
            .fontWeight(boldTextEnabled ? escalated(from: base) : base)
    }

    private func escalated(from weight: Font.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight:  return .thin
        case .thin:        return .light
        case .light:       return .regular
        case .regular:     return .medium
        case .medium:      return .semibold
        case .semibold:    return .bold
        case .bold:        return .heavy
        case .heavy:       return .black
        case .black:       return .black
        default:           return .semibold  // fallback
        }
    }
}

// MARK: - DesignTokens.BoldText

extension DesignTokens {
    /// Helpers to select values based on Bold Text state.
    public enum BoldText {
        /// Returns `bold` when Bold Text is active, `normal` otherwise.
        public static func select<T>(normal: T, bold: T, isBold: Bool) -> T {
            isBold ? bold : normal
        }

        /// Font-weight step-up table per §80.
        public static func weight(for base: Font.Weight, isBold: Bool) -> Font.Weight {
            guard isBold else { return base }
            switch base {
            case .ultraLight:  return .thin
            case .thin:        return .light
            case .light:       return .regular
            case .regular:     return .medium
            case .medium:      return .semibold
            case .semibold:    return .bold
            default:           return .heavy
            }
        }
    }
}
