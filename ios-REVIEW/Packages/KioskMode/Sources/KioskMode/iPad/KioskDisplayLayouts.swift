import SwiftUI
import DesignSystem

// MARK: - KioskDisplayVariant

/// §22 — The three display variants an iPad kiosk screen may adopt.
public enum KioskDisplayVariant: Sendable, Equatable {
    /// Single iPad, landscape orientation (primary kiosk orientation).
    case landscape
    /// Single iPad, portrait orientation.
    case portrait
    /// Dual-screen / Stage Manager split: a secondary companion panel is
    /// visible beside the main kiosk content.
    case dualScreen
}

// MARK: - KioskLayoutMetrics

/// Derived measurement tokens for a given `KioskDisplayVariant`.
/// All values are in SwiftUI points on an 8-pt grid.
public struct KioskLayoutMetrics: Sendable, Equatable {
    /// Horizontal outer padding for the main content region.
    public let horizontalPadding: CGFloat
    /// Vertical outer padding for the main content region.
    public let verticalPadding: CGFloat
    /// Width allocated to a companion sidebar (dualScreen only; 0 otherwise).
    public let sidebarWidth: CGFloat
    /// Preferred content column width when the layout splits into columns.
    public let contentColumnWidth: CGFloat
    /// Preferred spacing between major layout sections.
    public let sectionSpacing: CGFloat
    /// Whether the layout should render a sidebar alongside the main content.
    public let showsSidebar: Bool
    /// Maximum width for centered hero content (lock screen, branding).
    public let heroCenterMaxWidth: CGFloat

    public init(
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        sidebarWidth: CGFloat,
        contentColumnWidth: CGFloat,
        sectionSpacing: CGFloat,
        showsSidebar: Bool,
        heroCenterMaxWidth: CGFloat
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.sidebarWidth = sidebarWidth
        self.contentColumnWidth = contentColumnWidth
        self.sectionSpacing = sectionSpacing
        self.showsSidebar = showsSidebar
        self.heroCenterMaxWidth = heroCenterMaxWidth
    }
}

// MARK: - KioskDisplayVariant + metrics factory

public extension KioskDisplayVariant {
    /// Returns layout metrics appropriate for this variant.
    var metrics: KioskLayoutMetrics {
        switch self {
        case .landscape:
            return KioskLayoutMetrics(
                horizontalPadding: DesignTokens.Spacing.huge,   // 48
                verticalPadding:   DesignTokens.Spacing.xxxl,   // 32
                sidebarWidth:      0,
                contentColumnWidth: 600,
                sectionSpacing:    DesignTokens.Spacing.xxxl,   // 32
                showsSidebar:      false,
                heroCenterMaxWidth: 560
            )
        case .portrait:
            return KioskLayoutMetrics(
                horizontalPadding: DesignTokens.Spacing.xxxl,   // 32
                verticalPadding:   DesignTokens.Spacing.huge,   // 48
                sidebarWidth:      0,
                contentColumnWidth: 480,
                sectionSpacing:    DesignTokens.Spacing.xxl,    // 24
                showsSidebar:      false,
                heroCenterMaxWidth: 440
            )
        case .dualScreen:
            return KioskLayoutMetrics(
                horizontalPadding: DesignTokens.Spacing.xxxl,   // 32
                verticalPadding:   DesignTokens.Spacing.xxxl,   // 32
                sidebarWidth:      320,
                contentColumnWidth: 520,
                sectionSpacing:    DesignTokens.Spacing.xxl,    // 24
                showsSidebar:      true,
                heroCenterMaxWidth: 480
            )
        }
    }
}

// MARK: - KioskDisplayLayout view

/// §22 Root layout container for kiosk iPad content.
///
/// Selects between landscape, portrait, and dual-screen arrangements by
/// reading the `horizontalSizeClass` and `verticalSizeClass` environment
/// values, then exposing `KioskLayoutMetrics` down the tree via preference.
///
/// Usage:
/// ```swift
/// KioskDisplayLayout { metrics in
///     MyKioskContent(metrics: metrics)
/// }
/// ```
public struct KioskDisplayLayout<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    private let content: (KioskLayoutMetrics) -> Content
    /// Optional override — useful for previews and unit tests.
    private let variantOverride: KioskDisplayVariant?

    public init(
        variant override: KioskDisplayVariant? = nil,
        @ViewBuilder content: @escaping (KioskLayoutMetrics) -> Content
    ) {
        self.variantOverride = override
        self.content = content
    }

    public var body: some View {
        let variant = variantOverride ?? resolvedVariant
        let metrics = variant.metrics
        content(metrics)
            .environment(\.kioskDisplayVariant, variant)
    }

    // MARK: - Variant resolution

    private var resolvedVariant: KioskDisplayVariant {
        // Dual-screen / Stage Manager: both classes are .regular on iPad with
        // a companion window.  Detected here by checking if the horizontal
        // class is regular while screen is unusually narrow (handled by the
        // caller providing an override) — fall back to orientation heuristic.
        if hSizeClass == .regular && vSizeClass == .regular {
            return .landscape
        } else if hSizeClass == .compact {
            return .portrait
        } else {
            return .landscape
        }
    }
}

// MARK: - KioskDisplayVariant environment key

private struct KioskDisplayVariantKey: EnvironmentKey {
    static let defaultValue: KioskDisplayVariant = .landscape
}

public extension EnvironmentValues {
    var kioskDisplayVariant: KioskDisplayVariant {
        get { self[KioskDisplayVariantKey.self] }
        set { self[KioskDisplayVariantKey.self] = newValue }
    }
}

// MARK: - KioskDualScreenLayout

/// §22 Dual-screen compositor: places `primary` content on the left and a
/// `companion` panel on the right, separated by a glass divider.
///
/// On single-screen variants the companion is hidden and primary fills the
/// available width.
public struct KioskDualScreenLayout<Primary: View, Companion: View>: View {
    private let metrics: KioskLayoutMetrics
    private let primary: () -> Primary
    private let companion: () -> Companion

    public init(
        metrics: KioskLayoutMetrics,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder companion: @escaping () -> Companion
    ) {
        self.metrics = metrics
        self.primary = primary
        self.companion = companion
    }

    public var body: some View {
        if metrics.showsSidebar {
            HStack(spacing: 0) {
                primary()
                    .frame(maxWidth: .infinity)

                // Glass divider
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)

                companion()
                    .frame(width: metrics.sidebarWidth)
            }
        } else {
            primary()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
