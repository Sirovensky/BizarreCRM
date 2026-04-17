import SwiftUI
import Core
import DesignSystem

public struct TicketListView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 64))
                        .foregroundStyle(.bizarreOrange)
                        .padding(.top, BrandSpacing.xxl)

                    Text("Tickets")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)

                    Text("Open tickets across the shop.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)

                    Text("Phase 0 placeholder — wire up in a later phase.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.top, BrandSpacing.md)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Tickets")
        }
    }
}

#Preview {
    TicketListView()
        .preferredColorScheme(.dark)
}
