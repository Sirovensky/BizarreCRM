#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Temporary Charge sheet used until the BlockChyp SDK lands (§17.3). The
/// real flow will replace this with terminal pairing + charge call. Keeps
/// staff unblocked on rehearsing the UI; no fake success state — the sheet
/// just says "not yet wired" and dismisses.
struct PosChargePlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let totalCents: Int

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreOrange)
                        .padding(.top, BrandSpacing.xl)

                    Text(CartMath.formatCents(totalCents))
                        .font(.brandHeadlineLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()

                    Text("Charge flow not yet wired — BlockChyp SDK pending (§17).")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)

                    Spacer()

                    Button("Back to cart") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreOrange)
                        .controlSize(.large)
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.bottom, BrandSpacing.lg)
                        .accessibilityLabel("Return to cart")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
#endif
