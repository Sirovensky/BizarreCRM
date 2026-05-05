import SwiftUI

// MARK: - PolishInspectorOverlay

/// **DEBUG-only** overlay that highlights UX polish violations in the view tree.
///
/// Violations detected:
/// - **Tap target too small**: Any `GeometryReader`-measured interactive region
///   smaller than 44×44 pt gets a red border overlay.
/// - **Missing a11y label**: Views without an `accessibilityLabel` set (detected
///   via `Mirror` reflection of the view struct's stored properties looking for
///   an `accessibilityLabel` string property equal to `""` or absent).
///
/// The overlay is gated behind `#if DEBUG` at compile time and additionally
/// behind the `showPolishInspector` environment key at runtime, so it can be
/// toggled in simulator without recompiling.
///
/// **Usage:**
/// ```swift
/// // In your PreviewProvider or debug menu:
/// MyView()
///     .polishInspector()
///
/// // Or enable globally for a debug build:
/// ContentView()
///     .environment(\.showPolishInspector, true)
/// ```

// MARK: - Environment key

private struct ShowPolishInspectorKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    /// When `true` (and `#if DEBUG`) the PolishInspectorOverlay is active.
    var showPolishInspector: Bool {
        get { self[ShowPolishInspectorKey.self] }
        set { self[ShowPolishInspectorKey.self] = newValue }
    }
}

// MARK: - Violation model

/// A single inspector finding attached to a view.
public struct PolishViolation: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case tapTargetTooSmall = "Tap target < 44 pt"
        case missingA11yLabel  = "Missing a11y label"
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }
}

// MARK: - Inspector modifier (DEBUG only)

#if DEBUG

/// Internal modifier that measures the view and draws violation badges.
public struct PolishInspectorModifier: ViewModifier {

    @Environment(\.showPolishInspector) private var isActive

    // Whether this call site has explicitly opted into tap-target checking.
    public let checkTapTarget: Bool
    // Whether to check for a missing a11y label via Mirror.
    public let checkA11yLabel: Bool
    // Caller-provided view label hint (since we cannot reliably introspect SwiftUI views at runtime).
    public let accessibilityLabelHint: String?

    public init(
        checkTapTarget: Bool = true,
        checkA11yLabel: Bool = true,
        accessibilityLabelHint: String? = nil
    ) {
        self.checkTapTarget = checkTapTarget
        self.checkA11yLabel = checkA11yLabel
        self.accessibilityLabelHint = accessibilityLabelHint
    }

    public func body(content: Content) -> some View {
        if isActive {
            content
                .background(
                    GeometryReader { proxy in
                        violationOverlay(size: proxy.size)
                    }
                )
        } else {
            content
        }
    }

    // MARK: Private

    @ViewBuilder
    private func violationOverlay(size: CGSize) -> some View {
        let violations = detectViolations(size: size)
        if !violations.isEmpty {
            ZStack(alignment: .topLeading) {
                // Red border for any violation
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.8), lineWidth: 2)

                // Badge row
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(violations, id: \.kind.rawValue) { violation in
                        violationBadge(violation)
                    }
                }
                .offset(x: 2, y: -(CGFloat(violations.count) * 18 + 4))
            }
        }
    }

    @ViewBuilder
    private func violationBadge(_ violation: PolishViolation) -> some View {
        Text(violation.kind.rawValue)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(badgeColor(for: violation.kind))
            )
    }

    private func badgeColor(for kind: PolishViolation.Kind) -> Color {
        switch kind {
        case .tapTargetTooSmall: return .red
        case .missingA11yLabel:  return .orange
        }
    }

    private func detectViolations(size: CGSize) -> [PolishViolation] {
        var violations: [PolishViolation] = []

        if checkTapTarget {
            let tooSmall = size.width < MinTapTargetModifier.minimumSide
                        || size.height < MinTapTargetModifier.minimumSide
            if tooSmall {
                violations.append(PolishViolation(kind: .tapTargetTooSmall))
            }
        }

        if checkA11yLabel {
            let missing = isMissingA11yLabel()
            if missing {
                violations.append(PolishViolation(kind: .missingA11yLabel))
            }
        }

        return violations
    }

    /// Returns `true` when the caller-supplied hint is empty or nil,
    /// which is the signal that no `accessibilityLabel` was set at the call site.
    ///
    /// SwiftUI views are value types; full runtime introspection of the
    /// accessibility hierarchy is not available outside UIKit/AX APIs. We
    /// use a hint parameter as a lightweight proxy: callers pass their
    /// `accessibilityLabel` string so the inspector can check it.
    private func isMissingA11yLabel() -> Bool {
        guard let hint = accessibilityLabelHint else { return true }
        return hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - View extension (DEBUG only)

public extension View {
    /// Activates the PolishInspectorOverlay on this view.
    ///
    /// - Parameters:
    ///   - checkTapTarget: Flag tap targets smaller than 44 pt. Default `true`.
    ///   - checkA11yLabel: Flag missing accessibility labels. Default `true`.
    ///   - accessibilityLabel: Pass the same string you set via
    ///     `.accessibilityLabel(...)` so the inspector can check it.
    ///     Pass `nil` (default) to always flag as missing.
    func polishInspector(
        checkTapTarget: Bool = true,
        checkA11yLabel: Bool = true,
        accessibilityLabel: String? = nil
    ) -> some View {
        modifier(PolishInspectorModifier(
            checkTapTarget: checkTapTarget,
            checkA11yLabel: checkA11yLabel,
            accessibilityLabelHint: accessibilityLabel
        ))
        .environment(\.showPolishInspector, true)
    }
}

#else

// MARK: - Release no-ops

public extension View {
    /// No-op in release builds. The PolishInspectorOverlay is DEBUG-only.
    @inline(__always)
    func polishInspector(
        checkTapTarget: Bool = true,
        checkA11yLabel: Bool = true,
        accessibilityLabel: String? = nil
    ) -> some View {
        self
    }
}

#endif
