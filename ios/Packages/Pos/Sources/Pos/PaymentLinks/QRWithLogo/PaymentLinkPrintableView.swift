#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §41.6 Printable payment reminder

/// Branded printable flyer: tenant logo + QR code + amount + expiry.
/// Designed for thermal printer (58 mm / 80 mm) or PDF export via
/// `ImageRenderer` / `fileExporter`.
///
/// iPhone: sheet with share button.
/// iPad: popped over or navigation detail with ⌘P shortcut.
public struct PaymentLinkPrintableView: View {
    let link: PaymentLink
    let branding: PaymentLinkBranding?

    @State private var qrImage: UIImage?
    @State private var showShare: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(link: PaymentLink, branding: PaymentLinkBranding? = nil) {
        self.link = link
        self.branding = branding
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                printable
                HStack(spacing: BrandSpacing.sm) {
                    ShareLink(
                        item: Image(uiImage: snapshot()),
                        preview: SharePreview(
                            "Payment QR for \(CartMath.formatCents(link.amountCents))",
                            image: Image(uiImage: snapshot())
                        )
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("printable.shareButton")
                }
                .controlSize(.large)
                .padding(.horizontal, BrandSpacing.base)
            }
            .padding(.vertical, BrandSpacing.lg)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Print / share")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardShortcut("p", modifiers: .command)
        .task { await generateQR() }
    }

    // MARK: - Printable card

    private var printable: some View {
        VStack(spacing: BrandSpacing.md) {
            // Logo
            if let logoUrl = branding?.logoUrl, let url = URL(string: logoUrl) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "building.2")
                        .font(.system(size: 32))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(height: 48)
                .accessibilityLabel("Tenant logo")
            }

            Text("Scan to pay")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            // QR code
            Group {
                if let qr = qrImage {
                    Image(uiImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .accessibilityLabel("Scan to pay \(CartMath.formatCents(link.amountCents))")
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bizarreSurface1)
                        .frame(width: 220, height: 220)
                        .overlay(ProgressView())
                }
            }
            .padding(BrandSpacing.sm)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))

            Text(CartMath.formatCents(link.amountCents))
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()

            if let expiresAt = link.expiresAt {
                Text("Expires: \(expiresAt.prefix(10))")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let footer = branding?.footerText, !footer.isEmpty {
                Text(footer)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }

            if let url = link.url.isEmpty ? nil : link.url {
                Text(url)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, BrandSpacing.base)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    // MARK: - Helpers

    private func generateQR() async {
        let urlString = link.url.isEmpty ? "/pay/\(link.shortId ?? "")" : link.url
        qrImage = BrandedQRGenerator.generate(urlString: urlString, size: 440)
    }

    /// Snapshot the printable card as a UIImage for sharing / printing.
    private func snapshot() -> UIImage {
        let renderer = ImageRenderer(content: printable)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage ?? UIImage()
    }
}
#endif
