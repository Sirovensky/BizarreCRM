import SwiftUI

public struct OfflineBanner: View {
    let isOffline: Bool

    public init(isOffline: Bool) {
        self.isOffline = isOffline
    }

    public var body: some View {
        if isOffline {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "wifi.slash")
                Text("Offline — changes will sync when connected")
                    .font(.brandLabelLarge())
            }
            .foregroundStyle(.bizarreOnOrange)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .brandGlass(.regular, tint: .bizarreWarning)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(BrandMotion.offlineBanner, value: isOffline)
        }
    }
}
