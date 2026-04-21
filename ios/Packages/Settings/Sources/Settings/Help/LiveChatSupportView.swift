import SwiftUI
import DesignSystem

// MARK: - LiveChatSupportView

/// Live chat support entry point.
/// MVP: placeholder view — "Live chat coming soon" per spec.
/// Future: embed live chat SDK when server supports it.
public struct LiveChatSupportView: View {

    public init() {}

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Live Chat Coming Soon")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text("We're working on real-time support chat.\nIn the meantime, tap \"Contact Support\" to reach us by email.")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }
        }
        .navigationTitle("Live Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        LiveChatSupportView()
    }
}
#endif
