import SwiftUI
import DesignSystem

// MARK: - DataBridgeLinkCard

/// Settings row that deep-links to the DataImport and DataExport packages.
/// Uses the `DataBridgeDeepLink` protocol seam — never imports those packages.
///
/// Liquid Glass chrome is applied to the action buttons only (not the row
/// itself, per `ios/CLAUDE.md` §"DON'T USE glass on list rows").
public struct DataBridgeLinkCard: View {

    private let deepLink: (any DataBridgeDeepLink)?

    public init(deepLink: (any DataBridgeDeepLink)? = DataBridgeHolder.current.deepLink) {
        self.deepLink = deepLink
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.base) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Data Transfer")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Import or export your CRM data")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            HStack(spacing: BrandSpacing.sm) {
                actionButton(
                    label: "Import",
                    icon: "square.and.arrow.down",
                    accessibilityId: "dataBridge.openImport"
                ) {
                    deepLink?.openImport()
                }

                actionButton(
                    label: "Export",
                    icon: "square.and.arrow.up",
                    accessibilityId: "dataBridge.openExport"
                ) {
                    deepLink?.openExport()
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Data Transfer")
    }

    @ViewBuilder
    private func actionButton(
        label: String,
        icon: String,
        accessibilityId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .brandGlass(.clear, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }
}
