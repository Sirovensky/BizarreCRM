#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §2 Session timeout — floating warning banner shown in the final 60 seconds
/// of the idle window.
///
/// Attach to the root view via `.overlay(alignment: .top)` or inside a `ZStack`.
///
/// ```swift
/// ZStack(alignment: .top) {
///     MainContent()
///     SessionTimeoutWarningBanner(secondsRemaining: remaining) {
///         await sessionTimer.touch()
///     }
/// }
/// ```
public struct SessionTimeoutWarningBanner: View {

    /// Seconds remaining in the session. When this drops below 60 the banner
    /// animates in; when it hits 0 the caller should sign out.
    public let secondsRemaining: TimeInterval

    /// Called when the user taps "Extend" — caller should invoke `timer.touch()`.
    public let onExtend: () async -> Void

    private var isVisible: Bool { secondsRemaining > 0 && secondsRemaining <= 60 }

    public init(secondsRemaining: TimeInterval, onExtend: @escaping () async -> Void) {
        self.secondsRemaining = secondsRemaining
        self.onExtend = onExtend
    }

    public var body: some View {
        if isVisible {
            banner
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(
                    Animation.spring(response: 0.4, dampingFraction: 0.8),
                    value: isVisible
                )
        }
    }

    private var banner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.bizarreWarning)
                .accessibilityHidden(true)

            Text("Session expires in \(Int(secondsRemaining.rounded())) seconds")
                .font(.brandLabelSmall().bold())
                .foregroundStyle(Color.bizarreOnSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Button {
                Task { await onExtend() }
            } label: {
                Text("Extend")
                    .font(.brandLabelSmall().bold())
                    .foregroundStyle(Color.bizarreOrange)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .brandGlass(.regular, in: Capsule(), interactive: true)
            }
            .accessibilityLabel("Extend session")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 14), tint: Color.bizarreWarning.opacity(0.12))
        .padding(.horizontal, BrandSpacing.base)
        .padding(.top, BrandSpacing.xs)
    }
}
#endif
