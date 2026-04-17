import SwiftUI
import Core
import DesignSystem

public struct PhotoCaptureView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    Image(systemName: "camera")
                        .font(.system(size: 64))
                        .foregroundStyle(.bizarreOrange)
                        .padding(.top, BrandSpacing.xxl)

                    Text("Photo Capture")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)

                    Text("Before/after photos attached to tickets.")
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
            .navigationTitle("Photo Capture")
        }
    }
}

#Preview {
    PhotoCaptureView()
        .preferredColorScheme(.dark)
}
