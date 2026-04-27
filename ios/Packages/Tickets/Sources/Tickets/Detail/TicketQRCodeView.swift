#if canImport(UIKit)
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem

// §4.2: QR code — render ticket order-ID as QR via CoreImage;
// tap → full-screen enlarge for counter printer.
// `Image(uiImage: ...)` + plaintext order ID below.

// MARK: - TicketQRCodeView

/// Compact QR code tile shown on the Ticket Detail screen.
/// Tap to enlarge in a full-screen modal (useful for counter printers).
public struct TicketQRCodeView: View {
    let orderId: String
    let size: CGFloat

    @State private var showingFullScreen: Bool = false

    public init(orderId: String, size: CGFloat = 120) {
        self.orderId = orderId
        self.size = size
    }

    public var body: some View {
        Button {
            showingFullScreen = true
        } label: {
            VStack(spacing: BrandSpacing.xs) {
                if let qrImage = generateQR(from: orderId) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .padding(BrandSpacing.sm)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                } else {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(Color.bizarreSurface1)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: "qrcode")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .font(.system(size: 32))
                        }
                }
                Text(orderId)
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("QR code for ticket \(orderId). Tap to enlarge.")
        .fullScreenCover(isPresented: $showingFullScreen) {
            TicketQRCodeFullScreenView(orderId: orderId)
        }
    }

    // MARK: - QR generation

    /// Generates a QR code UIImage encoding `text` using CoreImage.
    static func generate(from text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.correctionLevel = "M"
        guard let data = text.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        guard let outputImage = filter.outputImage else { return nil }
        // Scale up for crispness (QR is 1pt per module; scale × 10 = 10pt per module)
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func generateQR(from text: String) -> UIImage? {
        Self.generate(from: text)
    }
}

// MARK: - TicketQRCodeFullScreenView

/// Full-screen QR code for counter printers. Dismiss via swipe or X button.
private struct TicketQRCodeFullScreenView: View {
    let orderId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            VStack(spacing: BrandSpacing.xl) {
                // Dismiss button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .accessibilityLabel("Close")
                    .padding(BrandSpacing.base)
                }

                Spacer()

                if let qrImage = TicketQRCodeView.generate(from: orderId) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 320)
                        .padding(BrandSpacing.lg)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                        .accessibilityLabel("QR code for ticket \(orderId)")
                } else {
                    Text("Could not generate QR code")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Text(orderId)
                    .font(.brandMono(size: 20))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .padding(.top, BrandSpacing.md)

                Text("Scan or hand this to the counter printer")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                Spacer()
            }
        }
    }
}
#endif
