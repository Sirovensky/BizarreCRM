#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §Agent-E — Reusable glass share tile. Used in the 4-up grid on
/// `PosReceiptView`. The `isPrimary` flag adds a cream/orange bloom on the
/// SMS tile (dark mode: cream; light mode: orange).
///
/// Accessibility: the tile is a `Button` with a combined label so VoiceOver
/// reads "Text receipt, button" rather than announcing the icon and label
/// separately.
public struct PosShareTile: View {
    public let systemImage: String
    public let label: String
    public let isPrimary: Bool
    public let action: () -> Void

    public init(
        systemImage: String,
        label: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.isPrimary = isPrimary
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isPrimary ? .bizarreOnOrange : .bizarreOnSurface)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isPrimary ? .bizarreOnOrange : .bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, BrandSpacing.md)
            .padding(.horizontal, BrandSpacing.sm)
            .background(primaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isPrimary ? Color.bizarreOrange.opacity(0.6) : Color.bizarreOutline.opacity(0.4),
                        lineWidth: isPrimary ? 1 : 0.5
                    )
            )
            .brandGlass(isPrimary ? .identity : .regular, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) receipt")
        .accessibilityHint("Send receipt via \(label)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var primaryBackground: some View {
        if isPrimary {
            Color.bizarreOrange.opacity(0.18)
        } else {
            Color.bizarreSurface1.opacity(0.8)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        PosShareTile(systemImage: "message.fill", label: "Text", isPrimary: true) {}
        PosShareTile(systemImage: "envelope", label: "Email") {}
        PosShareTile(systemImage: "printer", label: "Print") {}
        PosShareTile(systemImage: "airplayaudio", label: "AirDrop") {}
    }
    .padding()
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
