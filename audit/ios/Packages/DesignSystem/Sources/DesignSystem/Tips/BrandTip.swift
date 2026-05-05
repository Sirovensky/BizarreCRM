// DesignSystem/Tips/BrandTip.swift
//
// Base protocol for all BizarreCRM TipKit tips.
// Provides a typed wrapper around the raw TipKit.Tip protocol so that
// every tip in the catalog has a consistent shape and testable properties.
//
// iOS 17+ / TipKit (Apple framework — no third-party dependency).
// §26 Sticky a11y tips

#if canImport(TipKit)
import TipKit

/// A BizarreCRM tip that conforms to the system `TipKit.Tip` protocol.
///
/// Callers implement `var title`, `var message`, and `var image` returning
/// typed `TipKit.Tips.InfoText` / `TipKit.Tips.InfoImage` values, then layer
/// on `@Parameter` and `rules` for eligibility.
///
/// Example:
/// ```swift
/// struct MyFeatureTip: BrandTip {
///     static let viewed = Event(id: "my_feature_viewed")
///     var rules: [Rule] {
///         [#Rule(Self.viewed) { $0.donations.count >= 3 }]
///     }
///     var title: Text { Text("Try this feature") }
///     var message: Text? { Text("It makes things faster.") }
///     var image: Image? { Image(systemName: "star") }
/// }
/// ```
public protocol BrandTip: Tip {}
#endif // canImport(TipKit)
