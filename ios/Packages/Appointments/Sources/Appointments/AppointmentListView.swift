import SwiftUI
import Core
import DesignSystem

public struct AppointmentListView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    Image(systemName: "calendar")
                        .font(.system(size: 64))
                        .foregroundStyle(.bizarreOrange)
                        .padding(.top, BrandSpacing.xxl)

                    Text("Appointments")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)

                    Text("Upcoming appointments.")
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
            .navigationTitle("Appointments")
        }
    }
}

#Preview {
    AppointmentListView()
        .preferredColorScheme(.dark)
}
