#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - PosCatalogStaleBannerView

/// §16.12 Stop-sell banner shown in POS chrome when the catalog cache is older
/// than 24 hours.
///
/// The cashier sees a dismissible amber warning with a "Sync now" CTA. Dismissing
/// or syncing hides the banner; the sale is never hard-blocked from the client
/// (server validates pricing on checkout).
///
/// ## Accessibility
/// The banner announces itself with VoiceOver as a warning. The "Sync now" button
/// triggers the `onSync` callback.  The "Dismiss" button hides the banner until
/// the next staleness check.
///
/// ## Placement
/// Insert at the top of `PosSearchPanel` (below the toolbar, above the category
/// chips row) when `state.isStale == true`.
///
/// ```swift
/// if catalogState.isStale {
///     PosCatalogStaleBannerView(state: catalogState, onSync: { await vm.syncCatalog() })
/// }
/// ```
public struct PosCatalogStaleBannerView: View {
    public let state: CatalogStalenessState
    public let onSync: @MainActor () -> Void

    @State private var dismissed = false

    public init(state: CatalogStalenessState, onSync: @escaping @MainActor () -> Void) {
        self.state  = state
        self.onSync = onSync
    }

    public var body: some View {
        if !dismissed, state.isStale, let message = state.bannerText {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onSync()
                } label: {
                    Text("Sync")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarrePrimary)
                }
                .accessibilityLabel("Sync catalog now")
                .accessibilityIdentifier("posCatalogStale.sync")

                Button {
                    withAnimation(.easeOut(duration: DesignTokens.Motion.snappy)) {
                        dismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Dismiss catalog warning")
                .accessibilityIdentifier("posCatalogStale.dismiss")
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bizarreWarning.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(Color.bizarreWarning.opacity(0.35), lineWidth: 1)
                    )
            )
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel("Catalog price warning: \(message)")
        }
    }
}
#endif
