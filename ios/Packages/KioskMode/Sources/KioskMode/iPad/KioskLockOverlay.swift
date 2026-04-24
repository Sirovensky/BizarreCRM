import SwiftUI
import DesignSystem

// MARK: - KioskLockOverlayConfig

/// §22 Configuration for the full-bleed kiosk idle / lock screen.
public struct KioskLockOverlayConfig: Sendable, Equatable {
    /// Primary business name shown in the hero.
    public let businessName: String
    /// Optional tagline shown below the business name.
    public let tagline: String?
    /// System name of the hero icon.
    public let iconSystemName: String
    /// Whether the overlay is currently in "blackout" mode (full dark) or
    /// "attract" mode (branded idle screen).
    public let mode: KioskLockMode

    public init(
        businessName: String,
        tagline: String? = nil,
        iconSystemName: String = "bolt.fill",
        mode: KioskLockMode = .attract
    ) {
        self.businessName = businessName
        self.tagline = tagline
        self.iconSystemName = iconSystemName
        self.mode = mode
    }
}

// MARK: - KioskLockMode

public enum KioskLockMode: Sendable, Equatable {
    /// Branded attract screen — visible branding, ambient animation.
    case attract
    /// Full blackout — maximum OLED power saving, minimal chrome.
    case blackout
}

// MARK: - KioskLockOverlay

/// §22 Full-bleed kiosk idle / attract screen for iPad.
///
/// Shown when `KioskIdleMonitor.idleState` is `.dimmed` (attract) or
/// `.blackout`. Tapping anywhere wakes the device and calls `onWake`.
///
/// Liquid Glass chrome: the "Tap to wake" pill uses `.brandGlass(.regular)`.
/// The hero icon and business name use `burnInNudge` to prevent OLED damage.
public struct KioskLockOverlay: View {
    private let config: KioskLockOverlayConfig
    private let metrics: KioskLayoutMetrics
    private let onWake: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var attractPulse = false

    public init(
        config: KioskLockOverlayConfig,
        metrics: KioskLayoutMetrics,
        onWake: @escaping () -> Void
    ) {
        self.config = config
        self.metrics = metrics
        self.onWake = onWake
    }

    public var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onWake() }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            guard !reduceMotion, config.mode == .attract else { return }
            withAnimation(
                .easeInOut(duration: DesignTokens.Motion.slow)
                .repeatForever(autoreverses: true)
            ) {
                attractPulse = true
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        switch config.mode {
        case .attract:
            Color.black
                .overlay {
                    // Subtle radial gradient brand accent
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 480
                    )
                    .scaleEffect(attractPulse ? 1.1 : 0.9)
                    .animation(
                        reduceMotion
                            ? .none
                            : .easeInOut(duration: DesignTokens.Motion.slow)
                                .repeatForever(autoreverses: true),
                        value: attractPulse
                    )
                }
        case .blackout:
            Color.black
        }
    }

    // MARK: - Hero content

    @ViewBuilder
    private var contentLayer: some View {
        VStack(spacing: DesignTokens.Spacing.xxxl) {
            Spacer()

            heroIcon
            brandingStack
            wakePrompt

            Spacer()
        }
        .frame(maxWidth: metrics.heroCenterMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var heroIcon: some View {
        Image(systemName: config.iconSystemName)
            .font(.system(size: 72, weight: .semibold))
            .foregroundStyle(
                config.mode == .blackout
                    ? Color.white.opacity(0.3)
                    : Color.orange
            )
            .burnInNudge(every: 30)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var brandingStack: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Text(config.businessName)
                .font(.system(size: 48, weight: .bold, design: .default))
                .foregroundStyle(
                    config.mode == .blackout
                        ? Color.white.opacity(0.4)
                        : Color.white
                )
                .multilineTextAlignment(.center)
                .burnInNudge(every: 30)

            if let tagline = config.tagline {
                Text(tagline)
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .burnInNudge(every: 30)
            }
        }
    }

    private var wakePrompt: some View {
        Text("Tap anywhere to wake")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .brandGlass(.clear, tint: nil, interactive: false)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch config.mode {
        case .attract: return "Screen is idle — tap to wake"
        case .blackout: return "Screen is sleeping — tap to wake"
        }
    }
}
