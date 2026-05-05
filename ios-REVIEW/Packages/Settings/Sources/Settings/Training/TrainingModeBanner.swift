import SwiftUI
import DesignSystem

// MARK: - TrainingModeBanner

/// Persistent sticky banner shown at the top of any screen while
/// Training Mode is active.
///
/// This is a **reusable, self-contained** view — callers place it wherever
/// it makes sense, guarded by the `isEnabled` flag:
///
/// ```swift
/// VStack(spacing: 0) {
///     if settings.isEnabled {
///         TrainingModeBanner()
///     }
///     contentView
/// }
/// ```
///
/// The banner uses `.brandGlass` Liquid Glass chrome (orange tint) per the
/// iOS visual language rules and the `OfflineBanner` precedent.
///
/// iPad layout widens the chip to fill available width; iPhone clips to the
/// safe-area width. Both use the same glass treatment.
public struct TrainingModeBanner: View {

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)

            Text("Training Mode — no real data will be modified")
                .font(.brandLabelLarge())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.bizarreOnOrange)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: bannerMaxWidth)
        .brandGlass(.regular, in: Capsule(), tint: .bizarreWarning)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.top, BrandSpacing.xs)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: true)
        .accessibilityLabel("Training Mode active. No real data will be modified.")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("trainingMode.banner")
    }

    // MARK: - Layout helpers

    /// On iPad (regular width), the banner pill has an upper bound so it
    /// doesn't stretch absurdly across a full 12.9" display.
    private var bannerMaxWidth: CGFloat? {
        hSizeClass == .regular ? 520 : .infinity
    }
}
