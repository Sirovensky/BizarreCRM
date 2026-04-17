import SwiftUI
import Core
import DesignSystem

public struct GlobalSearchView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundStyle(.bizarreOrange)
                        .padding(.top, BrandSpacing.xxl)

                    Text("Search")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)

                    Text("Global search across tickets, customers, inventory.")
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
            .navigationTitle("Search")
        }
    }
}

#Preview {
    GlobalSearchView()
        .preferredColorScheme(.dark)
}
