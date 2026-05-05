import SwiftUI

// MARK: - EmptyStateAction

/// A single action button on an empty-state card. Immutable value type.
public struct EmptyStateAction: Sendable {
    public let label: String
    public let systemImage: String?
    public let action: @Sendable @MainActor () -> Void

    public init(label: String, systemImage: String? = nil, action: @escaping @Sendable @MainActor () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }
}

// MARK: - EmptyStateCard

/// Reusable empty-state card used across all list screens.
///
/// Variants:
/// - Standard (icon + title + message + optional CTAs)
/// - Error (red icon tint, error message + retry)
/// - Onboarding (animated pulse on icon)
///
/// **Usage:**
/// ```swift
/// EmptyStateCard(
///     icon: "ticket",
///     title: "No tickets yet",
///     message: "Add your first repair job to get started.",
///     primaryAction: EmptyStateAction(label: "Add Ticket", systemImage: "plus") { viewModel.addTicket() }
/// )
/// ```
public struct EmptyStateCard: View {
    public enum Variant: Sendable {
        case standard
        case error
        case onboarding
    }

    public let icon: String
    public let title: String
    public let message: String
    public let variant: Variant
    public let primaryAction: EmptyStateAction?
    public let secondaryAction: EmptyStateAction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        icon: String,
        title: String,
        message: String,
        variant: Variant = .standard,
        primaryAction: EmptyStateAction? = nil,
        secondaryAction: EmptyStateAction? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.variant = variant
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            iconView
            textBlock
            actionButtons
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: 400)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Subviews

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 72, height: 72)

            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(iconForegroundColor)
                .accessibilityHidden(true)
        }
        .modifier(OnboardingPulseModifier(active: variant == .onboarding && !reduceMotion))
    }

    private var textBlock: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if primaryAction != nil || secondaryAction != nil {
            VStack(spacing: DesignTokens.Spacing.sm) {
                if let primary = primaryAction {
                    Button(action: primary.action) {
                        Label {
                            Text(primary.label)
                        } icon: {
                            if let img = primary.systemImage {
                                Image(systemName: img)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if let secondary = secondaryAction {
                    Button(action: secondary.action) {
                        Label {
                            Text(secondary.label)
                        } icon: {
                            if let img = secondary.systemImage {
                                Image(systemName: img)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.bizarreTeal)
                }
            }
        }
    }

    // MARK: Helpers

    private var iconBackgroundColor: Color {
        switch variant {
        case .standard:   return Color.bizarreSurface2
        case .error:      return Color.bizarreError.opacity(0.15)
        case .onboarding: return Color.bizarreOrangeContainer
        }
    }

    private var iconForegroundColor: Color {
        switch variant {
        case .standard:   return Color.bizarreOnSurfaceMuted
        case .error:      return Color.bizarreError
        case .onboarding: return Color.bizarreOrange
        }
    }

    private var accessibilitySummary: String {
        var parts = [title, message]
        if let p = primaryAction { parts.append(p.label) }
        if let s = secondaryAction { parts.append(s.label) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - OnboardingPulseModifier

private struct OnboardingPulseModifier: ViewModifier {
    let active: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        if active {
            content
                .scaleEffect(pulsing ? 1.07 : 1.0)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: DesignTokens.Motion.slow)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulsing = true
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Convenience constructors

public extension EmptyStateCard {
    /// Pre-built error variant with a retry action.
    static func error(
        title: String = "Something went wrong",
        message: String = "Tap to try again.",
        retry: @escaping @Sendable @MainActor () -> Void
    ) -> EmptyStateCard {
        EmptyStateCard(
            icon: "exclamationmark.triangle.fill",
            title: title,
            message: message,
            variant: .error,
            primaryAction: EmptyStateAction(label: "Retry", systemImage: "arrow.clockwise", action: retry)
        )
    }
}
