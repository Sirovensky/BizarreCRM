import SwiftUI
import DesignSystem

// MARK: - TrainingModeWatermarkOverlay

/// §51.1 Semi-transparent orange banner pinned to the top safe area.
/// Announces to VoiceOver that the app is in training mode.
public struct TrainingModeWatermarkOverlay: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            banner
            Spacer()
        }
    }

    private var banner: some View {
        Text("Training mode — no real charges, no real SMS")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .dynamicTypeSize(.xSmall ... .accessibility2)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                Color.orange
                    .brandGlass(.regular, in: Rectangle(), tint: .orange)
                    .opacity(0.92)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Training mode is active. No real charges or SMS messages will be sent.")
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - View modifier

public extension View {
    /// Overlays the training mode watermark banner at the top of the view
    /// when `isActive` is true. Safe-area insets are respected.
    @ViewBuilder
    func trainingModeWatermark(isActive: Bool) -> some View {
        if isActive {
            overlay(alignment: .top) {
                TrainingModeWatermarkOverlay()
                    .ignoresSafeArea(edges: .top)
            }
        } else {
            self
        }
    }
}
