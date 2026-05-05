import SwiftUI

// §63 Draft recovery — DraftRecoveryBanner
// Phase 0 foundation
//
// A11y: full VoiceOver + Dynamic Type.
// Motion: respects Reduce Motion via @Environment(\.accessibilityReduceMotion).
// Design tokens: BrandSpacing / Color.bizarreAccent* / Font.brand*.

/// A sticky banner shown at the top of a screen when a draft is available.
///
/// Usage:
/// ```swift
/// var body: some View {
///     VStack(spacing: 0) {
///         if let record = draftRecord {
///             DraftRecoveryBanner(record: record) {
///                 viewModel.restoreDraft()
///             } onDiscard: {
///                 viewModel.discardDraft()
///             }
///         }
///         // … rest of screen content
///     }
/// }
/// ```
public struct DraftRecoveryBanner: View {
    public let record: DraftRecord
    public let onRestore: () -> Void
    public let onDiscard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        record: DraftRecord,
        onRestore: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.record = record
        self.onRestore = onRestore
        self.onDiscard = onDiscard
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.badge.clock")
                .foregroundStyle(Color.bizarreAccentPrimary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Unsaved draft")
                    .font(brandFont(.body, weight: .semibold))
                    .foregroundStyle(Color.bizarreLabelPrimary)
                Text(relativeTime)
                    .font(brandFont(.caption))
                    .foregroundStyle(Color.bizarreLabelSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Unsaved draft from \(relativeTime)")

            Spacer()

            Button("Restore") { onRestore() }
                .font(brandFont(.body, weight: .medium))
                .foregroundStyle(Color.bizarreAccentPrimary)
                .accessibilityHint("Restores your unsaved changes")
                .buttonStyle(.plain)

            Button("Discard") { onDiscard() }
                .font(brandFont(.body))
                .foregroundStyle(Color.bizarreLabelSecondary)
                .accessibilityHint("Discards the unsaved draft permanently")
                .buttonStyle(.plain)
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurfaceElevated)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: — Private

    private var relativeTime: String {
        RelativeDateTimeFormatter().localizedString(for: record.updatedAt, relativeTo: Date())
    }
}

// MARK: — View modifier convenience

extension View {
    /// Attach draft-recovery banner logic to a screen conforming to `DraftRecoverable`.
    @ViewBuilder
    public func draftRecoverable(
        record: DraftRecord?,
        onRestore: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) -> some View {
        if let record {
            VStack(spacing: 0) {
                DraftRecoveryBanner(record: record, onRestore: onRestore, onDiscard: onDiscard)
                self
            }
        } else {
            self
        }
    }
}

// MARK: — Design token stubs (compile-time placeholders until DesignSystem is wired)
// These extensions are declared with `fileprivate` so they don't leak into
// the broader module and don't conflict when DesignSystem provides real values.

fileprivate extension Color {
    static let bizarreAccentPrimary   = Color.accentColor
    static let bizarreLabelPrimary    = Color.primary
    static let bizarreLabelSecondary  = Color.secondary
    static let bizarreSurfaceElevated = Color.secondary.opacity(0.1)
}

fileprivate enum BrandSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

// Named separately to avoid ambiguity with SwiftUI.Font.Weight.
fileprivate enum BrandFontWeight { case regular, medium, semibold, bold }
fileprivate enum BrandFontStyle  { case body, caption, headline }

fileprivate func brandFont(_ style: BrandFontStyle, weight: BrandFontWeight = .regular) -> Font {
    switch style {
    case .body:
        switch weight {
        case .semibold: return Font.body.weight(.semibold)
        case .medium:   return Font.body.weight(.medium)
        default:        return Font.body
        }
    case .caption:  return Font.caption
    case .headline: return Font.headline
    }
}
