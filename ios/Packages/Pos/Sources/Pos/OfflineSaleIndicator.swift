#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Sync

// MARK: - OfflineSaleIndicator

/// Glass chip shown in the POS cart header when there are pending offline sales.
/// Tapping it opens `OfflineSaleQueueView`. Per CLAUDE.md: glass on chrome only.
///
/// Usage — embed in a toolbar or `safeAreaInset`:
/// ```swift
/// OfflineSaleIndicator(queueCount: syncManager.pendingCount) {
///     showingOfflineQueue = true
/// }
/// ```
public struct OfflineSaleIndicator: View {
    public let queueCount: Int
    public let onTap: () -> Void

    public init(queueCount: Int, onTap: @escaping () -> Void) {
        self.queueCount = queueCount
        self.onTap = onTap
    }

    public var body: some View {
        if queueCount > 0 {
            Button(action: onTap) {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityHidden(true)

                    Text(label)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreWarning.opacity(0.2), in: Capsule())
                .brandGlass(.clear, in: Capsule(), tint: .bizarreWarning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Double tap to review queued offline sales.")
            .accessibilityIdentifier("pos.offlineSaleIndicator")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeInOut(duration: DesignTokens.Motion.snappy), value: queueCount)
        }
    }

    private var label: String {
        queueCount == 1
            ? "1 offline sale queued"
            : "\(queueCount) offline sales queued"
    }

    private var accessibilityLabel: String {
        queueCount == 1
            ? "Offline sale queued. 1 sale will sync when online."
            : "Offline sales queued. \(queueCount) sales will sync when online."
    }
}

#Preview {
    VStack(spacing: 20) {
        OfflineSaleIndicator(queueCount: 1) {}
        OfflineSaleIndicator(queueCount: 3) {}
    }
    .padding()
    .background(Color.bizarreSurfaceBase)
}
#endif
