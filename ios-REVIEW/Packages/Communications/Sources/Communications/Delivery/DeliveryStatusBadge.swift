import SwiftUI
import DesignSystem

// MARK: - DeliveryStatusBadge

/// Reusable Liquid Glass–styled badge showing SMS delivery status.
/// Obeys Reduce Transparency — falls back to opaque surface when enabled.
public struct DeliveryStatusBadge: View {
    public let status: DeliveryStatus
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(status: DeliveryStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(status.displayLabel)
                .font(.brandMono(size: 11))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(backgroundView)
        .clipShape(Capsule())
        .accessibilityLabel("Delivery status: \(status.displayLabel)")
    }

    private var foregroundColor: Color {
        switch status {
        case .delivered:  return .bizarreOrange
        case .failed, .optedOut: return .bizarreError
        default: return .bizarreOnSurfaceMuted
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if reduceTransparency {
            Capsule().fill(Color.bizarreSurface2)
        } else {
            Capsule().fill(Color.bizarreSurface2.opacity(0.7))
        }
    }
}

// MARK: - Preview helper (debug only)

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        ForEach(DeliveryStatus.allCases, id: \.self) { s in
            DeliveryStatusBadge(status: s)
        }
    }
    .padding()
    .background(Color.bizarreSurfaceBase)
}
#endif
