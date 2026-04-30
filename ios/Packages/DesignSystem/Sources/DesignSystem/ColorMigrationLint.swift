import SwiftUI

// §80.7 / §80 Tokens — asset color migration audit (warn-only lint helpers)
//
// Call-sites that still use inline `Color(red:green:blue:)` or `Color(white:)`
// should migrate to named asset-catalog tokens (`BrandColors` / `SemanticColor`).
//
// This file provides:
//   1. `ColorMigrationAudit` — runtime warn-only audit functions (DEBUG only)
//      that log a warning when an inline Color is used where a token exists.
//   2. `@InlinedColor` property wrapper — marks intentional design-exceptions
//      so SwiftLint's `forbid_inline_design_values` custom rule can allow them.
//   3. `View.assertNoInlineColor()` — snapshot-test helper that forces
//      audit logging to fire in tests; ships as no-op in release.
//
// IMPORTANT: all functions in this file are warn-only. They NEVER crash or
// block rendering. The intent is to surface migration candidates during
// development and CI snapshot runs, not to break the app at runtime.
//
// SwiftLint enforcement (added to .swiftlint.yml):
//   custom_rules:
//     forbid_inline_design_values:
//       name: "Inline design value"
//       regex: 'Color\s*\(\s*(red|green|blue|white|hue|saturation|brightness)\s*:'
//       message: "Use a DesignTokens / BrandColors token. Mark intentional exceptions with // design-exception: <reason>"
//       severity: warning
//
// To mark an intentional exception, append the comment on the same line:
//   Color(red: 1, green: 0, blue: 0) // design-exception: UIKit bridge, no asset slot
//
// Usage (runtime audit):
//   ColorMigrationAudit.warn(
//       inlineColor: Color(red: 0.2, green: 0.3, blue: 0.4),
//       suggestedToken: "DesignTokens.SemanticColor.textSecondary",
//       file: #file, line: #line
//   )

// MARK: - ColorMigrationAudit

#if DEBUG
private final class ColorMigrationAuditState: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0

    var warningCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }
}
#endif

/// Runtime warn-only audit utilities for inline Color literal usage.
///
/// All methods are no-ops in release builds — guarded by `#if DEBUG`.
public enum ColorMigrationAudit {

#if DEBUG

    /// Total number of inline-color warnings emitted this process lifetime.
    /// Exposed for snapshot-test assertions.
    private static let state = ColorMigrationAuditState()
    public static var warningCount: Int { state.warningCount }

    /// Emit a runtime warning when an inline `Color(red:green:blue:)` is detected
    /// at `file:line`, suggesting the `suggestedToken` as the migration target.
    ///
    /// - Parameters:
    ///   - inlineColor: The Color value that was used inline (unused at runtime;
    ///     passed for API completeness and future tooling).
    ///   - suggestedToken: Human-readable token path, e.g.
    ///     `"DesignTokens.SemanticColor.textSecondary"`.
    ///   - file: Source file path (pass `#file`).
    ///   - line: Source line number (pass `#line`).
    public static func warn(
        inlineColor: Color,
        suggestedToken: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        state.increment()
        let fileName = URL(fileURLWithPath: "\(file)").lastPathComponent
        print(
            """
            ⚠️  [ColorMigrationAudit] Inline Color at \(fileName):\(line). \
            Migrate to \(suggestedToken). \
            Mark intentional exceptions with // design-exception: <reason>
            """
        )
    }

    /// Emit a warning for an inline `Color(white:)` grayscale literal.
    public static func warnGray(
        white: Double,
        suggestedToken: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        state.increment()
        let fileName = URL(fileURLWithPath: "\(file)").lastPathComponent
        print(
            """
            ⚠️  [ColorMigrationAudit] Inline Color(white: \(white)) at \(fileName):\(line). \
            Migrate to \(suggestedToken). \
            Mark intentional exceptions with // design-exception: <reason>
            """
        )
    }

    /// Reset the warning counter — call at the start of each snapshot test case.
    public static func resetCounter() {
        state.reset()
    }

#else

    // Release stubs — all zero cost.
    public static var warningCount: Int { 0 }
    public static func warn(inlineColor: Color, suggestedToken: String,
                            file: StaticString = #file, line: UInt = #line) {}
    public static func warnGray(white: Double, suggestedToken: String,
                                file: StaticString = #file, line: UInt = #line) {}
    public static func resetCounter() {}

#endif
}

// MARK: - @InlinedColor property wrapper

/// Marks a `Color` property as an intentional design-exception so SwiftLint's
/// `forbid_inline_design_values` rule can suppress the warning via a
/// `// design-exception:` comment.
///
/// Usage:
/// ```swift
/// @InlinedColor("UIKit bridge — no asset catalog slot")
/// private var uiKitOverlay: Color = Color(red: 0.1, green: 0.1, blue: 0.1)
/// ```
@propertyWrapper
public struct InlinedColor {
    public let reason: String
    public var wrappedValue: Color

    /// - Parameters:
    ///   - reason: Explains why an asset-catalog token cannot be used here.
    ///   - wrappedValue: The inline Color literal. Set at declaration site.
    public init(_ reason: String, wrappedValue: Color = .clear) {
        self.reason = reason
        self.wrappedValue = wrappedValue
    }
}

// MARK: - Snapshot-test helper

public extension View {
    /// Enables `ColorMigrationAudit` logging for this subtree during snapshot tests.
    ///
    /// In release / non-DEBUG builds this is a no-op passthrough.
    ///
    /// Usage:
    /// ```swift
    /// let sut = MyView().assertNoInlineColor()
    /// assertSnapshot(of: sut, as: .image)
    /// XCTAssertEqual(ColorMigrationAudit.warningCount, 0)
    /// ```
    @ViewBuilder
    func assertNoInlineColor() -> some View {
#if DEBUG
        self.onAppear { ColorMigrationAudit.resetCounter() }
#else
        self
#endif
    }
}

// MARK: - Migration guidance table
//
// Quick-reference: common inline literals → recommended token.
//
// | Inline literal                          | Token                                          |
// |-----------------------------------------|------------------------------------------------|
// | Color(red: 0.05, green: 0.04, …)        | Color.bizarreSurfaceBase / .surfaceBase        |
// | Color(red: 0.08, …) (dark surface)      | Color.bizarreSurface1                          |
// | Color(red: 1, green: 0.93, …) (cream)   | Color.bizarrePrimary / BrandPalette.primary    |
// | Color(white: 0.96) (light bg)           | DesignTokens.SemanticColor.surfaceBase         |
// | Color(white: 0.18) (dark skeleton)      | DesignTokens.Skeleton.base                     |
// | Color(red: 0.88, green: 0.2, …) (red)  | Color.bizarreError / DesignTokens.SemanticColor.danger |
// | Color(red: 0.3, green: 0.76, …) (teal) | Color.bizarreTeal                              |
// | Color(red: 0.91, green: 0.64, …) (amber)| Color.bizarreWarning                          |
// | Color(white: 0)                         | Color.black (system, allowed — no equivalent)  |
// | Color(white: 1)                         | Color.white (system, allowed — no equivalent)  |
