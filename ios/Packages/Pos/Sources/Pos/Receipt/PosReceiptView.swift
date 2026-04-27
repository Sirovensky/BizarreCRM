#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import CoreImage
import CoreImage.CIFilterBuiltins

/// §Agent-E — Receipt confirmation screen. Shown immediately after a tender
/// settles. Replaces (sits alongside) `PosPostSaleView` — the older view is
/// retained for the spinner/phase transition; this view is the settled state.
///
/// Layout (iPhone + iPad share the same scroll body; iPad gets the collapse
/// modifier on the cart column via the parent):
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │  SUCCESS HERO  (check glyph + amount)   │
/// ├─────────────────────────────────────────┤
/// │  SHARE 4-UP GRID (Text / Email / Print / AirDrop)│
/// ├─────────────────────────────────────────┤
/// │  LOYALTY CELEBRATION ROW (if pts > 0)   │
/// ├─────────────────────────────────────────┤
/// │  RECEIPT PREVIEW (monospace, scrollable)│
/// ├─────────────────────────────────────────┤
/// │  POST-SALE ACTION ROW                   │
/// └─────────────────────────────────────────┘
/// ```
///
/// Haptic: `.sensoryFeedback(.success, trigger: paidAt)` fires once on appear.
///
/// Accessibility: dynamic type is capped at `.accessibility2` for the hero
/// amount — beyond that the layout breaks and the cashier needs to read the
/// figure clearly at a glance.
@MainActor
public struct PosReceiptView: View {

    @Bindable var vm: PosReceiptViewModel

    /// Optional pre-rendered receipt text from `PosReceiptRenderer`. Used by
    /// the preview block and the share sheet. Pass `nil` to hide the preview.
    public let receiptText: String?

    /// Trigger for the success haptic. Set to `Date()` from the parent when
    /// the transaction settles.
    public let paidAt: Date

    /// Optional public tracking URL (from server invoice response `trackingToken`).
    /// When set, the QR code encodes this URL. Falls back to nil (no QR shown).
    public let trackingURL: URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    // MARK: - §16.7 PDF export
    @State private var pdfExportURL: URL?
    @State private var showingPdfExporter: Bool = false

    public init(
        vm: PosReceiptViewModel,
        receiptText: String? = nil,
        paidAt: Date = Date(),
        trackingURL: URL? = nil
    ) {
        self.vm = vm
        self.receiptText = receiptText
        self.paidAt = paidAt
        self.trackingURL = trackingURL
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            scrollBody
        }
        .sensoryFeedback(.success, trigger: paidAt)
        .accessibilityIdentifier("pos.receipt.root")
        // §16.7 — PDF download via fileExporter (only active when a PDF is ready)
        .modifier(ReceiptPDFExporterModifier(
            isPresented: $showingPdfExporter,
            url: $pdfExportURL,
            invoiceId: vm.payload.invoiceId
        ))
        .task(id: paidAt) {
            // §16.7 — Persist receipt model on first appear (keyed to paidAt so
            // re-renders don't cause duplicate writes).
            await persistReceiptModel()
        }
    }

    // MARK: - §16.7 — Persist receipt model

    private func persistReceiptModel() async {
        let model = ReceiptModelStore.StoredReceiptModel(
            invoiceId: vm.payload.invoiceId,
            receiptNumber: String(vm.payload.invoiceId),
            amountPaidCents: vm.payload.amountPaidCents,
            changeGivenCents: vm.payload.changeGivenCents,
            methodLabel: vm.payload.methodLabel,
            customerPhone: vm.payload.customerPhone,
            customerEmail: vm.payload.customerEmail,
            receiptText: receiptText
        )
        await ReceiptModelStore.shared.save(model)
    }

    // MARK: - §16.7 — PDF rendering

    private func exportPDF() {
        guard let text = receiptText else { return }
        let pdfData = renderReceiptPDF(text: text)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Receipt-\(vm.payload.invoiceId)-\(Self.isoDateString()).pdf")
        do {
            try pdfData.write(to: tempURL)
            pdfExportURL = tempURL
            showingPdfExporter = true
        } catch {
            AppLog.pos.error("Receipt PDF write failed: \(error.localizedDescription)")
        }
    }

    private func renderReceiptPDF(text: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            ]
            let lines = text
                .components(separatedBy: .newlines)
                .map { NSAttributedString(string: $0, attributes: attrs) }
            var yOffset: CGFloat = 32
            for line in lines {
                line.draw(at: CGPoint(x: 32, y: yOffset))
                yOffset += 14
                if yOffset > pageRect.height - 32 {
                    ctx.beginPage()
                    yOffset = 32
                }
            }
        }
    }

    private static func isoDateString() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: Date())
    }

    // MARK: - §16.7 — QR code generation

    /// Generates a QR-code `UIImage` from the tracking URL.
    /// Returns `nil` when `trackingURL` is absent.
    private var trackingQRImage: UIImage? {
        guard let url = trackingURL else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Scroll body

    private var scrollBody: some View {
        ScrollView {
            if sizeClass == .regular {
                // iPad: 2-column layout — left (hero + share + loyalty + actions) / right (receipt preview)
                iPadLayout
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xl)
            } else {
                // iPhone: single-column vertical stack
                iPhoneLayout
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xl)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - iPhone layout (single column)

    private var iPhoneLayout: some View {
        VStack(spacing: BrandSpacing.lg) {
            heroSection
            shareTileGrid
            downloadPDFButton
            qrCodeSection
            loyaltyCelebration
            if let text = receiptText {
                inlineReceiptPreview(text: text)
            }
            postSaleActionRow
        }
    }

    // MARK: - iPad layout (2-column)

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.lg) {
            // Left: hero + share + loyalty + pencil banner + post-sale actions
            VStack(spacing: BrandSpacing.lg) {
                heroSection
                shareTileGrid
                downloadPDFButton
                loyaltyCelebration
                pencilSignatureBanner
                postSaleActionRow
            }
            .frame(maxWidth: .infinity)

            // Right: inline receipt preview + QR code (lowest elevation per mockup)
            VStack(spacing: BrandSpacing.lg) {
                if let text = receiptText {
                    inlineReceiptPreview(text: text)
                }
                qrCodeSection
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - §16.7 — Download PDF button

    @ViewBuilder
    private var downloadPDFButton: some View {
        if receiptText != nil {
            Button {
                exportPDF()
            } label: {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 16, weight: .medium))
                    Text("Download PDF")
                        .font(.brandTitleSmall())
                }
                .foregroundStyle(.bizarreOrange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.bordered)
            .tint(.bizarreOrange)
            .accessibilityLabel("Download receipt as PDF")
            .accessibilityHint("Saves a PDF file to your chosen location")
            .accessibilityIdentifier("pos.receipt.downloadPDF")
        }
    }

    // MARK: - §16.7 — QR code section

    @ViewBuilder
    private var qrCodeSection: some View {
        if let qrImage = trackingQRImage {
            VStack(spacing: BrandSpacing.sm) {
                Text("Scan to track order")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .padding(BrandSpacing.sm)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Tracking QR code — customer can scan to track order")
                    .accessibilityIdentifier("pos.receipt.qrCode")
                if let url = trackingURL {
                    Text(url.absoluteString)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("pos.receipt.trackingURL")
                }
            }
            .padding(.vertical, BrandSpacing.md)
            .padding(.horizontal, BrandSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Pencil signature banner (iPad only)

    /// Teal banner shown on iPad receipt when a signature was captured via
    /// Apple Pencil (PKCanvasView). Matches mockup iPad screen 5.
    @ViewBuilder
    private var pencilSignatureBanner: some View {
        if sizeClass == .regular, let ticketId = vm.payload.signedTicketId {
            HStack(spacing: BrandSpacing.sm) {
                Text("✍")
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Signature captured with Pencil")
                        .font(.brandTitleSmall())
                        .foregroundStyle(Color.bizarreTeal)
                    Text("Archived to ticket #\(ticketId) · PKCanvasView")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, BrandSpacing.sm + 2)
            .padding(.horizontal, BrandSpacing.md)
            .background(Color.bizarreTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bizarreTeal.opacity(0.30), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Signature captured with Pencil and archived to ticket \(ticketId)")
            .accessibilityIdentifier("pos.receipt.pencilBanner")
        }
    }

    // MARK: - Hero

    /// Celebration hero — highest visual elevation per mockup spec.
    /// Glass container with radial success glow, "Payment complete" label,
    /// hero amount in Barlow Condensed, and cash change row.
    private var heroSection: some View {
        VStack(spacing: BrandSpacing.md) {
            // Radial glow behind check mark
            ZStack {
                RadialGradient(
                    colors: [Color.bizarreSuccess.opacity(0.40), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 90
                )
                .frame(width: 180, height: 180)
                .accessibilityHidden(true)

                Circle()
                    .fill(Color.bizarreSuccess.opacity(0.18))
                    .frame(width: 104, height: 104)
                    .accessibilityHidden(true)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
            }

            // "Payment complete" label — matches mockup
            Text("Payment complete")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("pos.receipt.completionLabel")

            // Amount — Barlow Condensed hero, Dynamic Type capped
            Text(CartMath.formatCents(vm.payload.amountPaidCents))
                .font(
                    .custom("BarlowCondensed-SemiBold", size: 60, relativeTo: .largeTitle)
                    .leading(.tight)
                )
                .dynamicTypeSize(.large ... .accessibility2)
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityLabel("Amount charged: \(CartMath.formatCents(vm.payload.amountPaidCents))")
                .accessibilityIdentifier("pos.receipt.amount")

            // Method + optional cash detail
            Text(cashDetailLabel)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pos.receipt.methodLabel")
        }
        .padding(.vertical, BrandSpacing.xl)
        .padding(.horizontal, BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            // Hero highest elevation: glass surface with success-tinted glow
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.bizarreSurface1.opacity(0.85))
                .overlay(
                    LinearGradient(
                        colors: [Color.bizarreSuccess.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.bizarreSuccess.opacity(0.35), lineWidth: 1)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pos.receipt.hero")
    }

    /// Label combining method + received + change for cash transactions.
    /// Matches mockup: "Cash · $300 received · $25.49 change".
    private var cashDetailLabel: String {
        var parts = [vm.payload.methodLabel]
        if let received = vm.payload.cashReceivedCents, received > 0 {
            parts.append("$\(String(format: "%.2f", Double(received) / 100)) received")
        }
        if let change = vm.payload.changeGivenCents, change > 0 {
            parts.append("$\(String(format: "%.2f", Double(change) / 100)) change")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Share tile grid

    private var shareTileGrid: some View {
        let isSmsPrimary = vm.defaultChannel == .sms
        let isEmailPrimary = vm.defaultChannel == .email

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: BrandSpacing.sm),
                GridItem(.flexible(), spacing: BrandSpacing.sm),
                GridItem(.flexible(), spacing: BrandSpacing.sm),
                GridItem(.flexible(), spacing: BrandSpacing.sm),
            ],
            spacing: BrandSpacing.sm
        ) {
            PosShareTile(
                systemImage: "message.fill",
                label: "Text",
                isPrimary: isSmsPrimary
            ) {
                vm.share(channel: .sms)
            }

            PosShareTile(
                systemImage: "envelope",
                label: "Email",
                isPrimary: isEmailPrimary
            ) {
                vm.share(channel: .email)
            }

            // Print: uses local UIPrintInteractionController
            printTile

            // AirDrop / system share sheet
            airDropTile
        }
        .accessibilityIdentifier("pos.receipt.shareGrid")
    }

    private var printTile: some View {
        PosShareTile(
            systemImage: "printer",
            label: "Print",
            isPrimary: vm.defaultChannel == .print
        ) {
            vm.share(channel: .print)
        }
        .overlay(
            Group {
                if vm.defaultChannel == .print, let text = receiptText {
                    PosPrintButton(
                        receiptText: text,
                        invoiceLabel: "INV-\(vm.payload.invoiceId)"
                    )
                    .opacity(0) // invisible — tap target backed by PosShareTile
                }
            }
        )
    }

    private var airDropTile: some View {
        Group {
            if let text = receiptText {
                // Wrap in ShareLink so tap opens the system share sheet.
                ShareLink(
                    item: text,
                    preview: SharePreview(
                        "Receipt INV-\(vm.payload.invoiceId)",
                        icon: Image(systemName: "airplayaudio")
                    )
                ) {
                    shareTileLabel(systemImage: "airplayaudio", label: "AirDrop")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AirDrop receipt")
                .accessibilityHint("Opens the system share sheet")
            } else {
                PosShareTile(systemImage: "airplayaudio", label: "AirDrop") {
                    vm.share(channel: .airDrop)
                }
            }
        }
    }

    private func shareTileLabel(systemImage: String, label: String) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.bizarreOnSurface)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.vertical, BrandSpacing.md)
        .padding(.horizontal, BrandSpacing.sm)
        .background(Color.bizarreSurface1.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Send status banner

    @ViewBuilder
    private var sendStatusBanner: some View {
        switch vm.sendStatus {
        case .sending:
            HStack(spacing: BrandSpacing.xs) {
                ProgressView().controlSize(.mini)
                Text("Sending…")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("pos.receipt.sendingSpinner")
        case .sent(let msg):
            Text(msg)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreSuccess)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pos.receipt.sentConfirmation")
        case .failed(let msg):
            Text(msg)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pos.receipt.sendError")
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Loyalty celebration

    @ViewBuilder
    private var loyaltyCelebration: some View {
        if let delta = vm.payload.loyaltyDelta, delta > 0 {
            VStack(spacing: BrandSpacing.xs) {
                sendStatusBanner
                PosLoyaltyCelebrationView(
                    pointsDelta: delta,
                    tierBefore: vm.payload.loyaltyTierBefore,
                    tierAfter: vm.payload.loyaltyTierAfter,
                    pointsTotal: vm.payload.loyaltyPointsTotal,
                    nextTierPoints: vm.payload.loyaltyNextTierPoints
                )
            }
        } else {
            sendStatusBanner
        }
    }

    // MARK: - Inline receipt preview

    /// Inline JetBrains Mono receipt block — matches mockup "receipt-list" section.
    /// Lower visual elevation than the hero per mockup spec.
    ///
    /// Passes the invoice number for the header ("RECEIPT #28014") and a
    /// "Sent ✓" chip when the most recent send succeeded.
    private func inlineReceiptPreview(text: String) -> some View {
        PosReceiptListPreview(
            receiptText: text,
            receiptNumber: String(vm.payload.invoiceId),
            sentChipLabel: sentChipLabel,
            footerText: "Thank you · 30-day returns with receipt"
        )
        .accessibilityIdentifier("pos.receipt.inlinePreview")
    }

    /// Returns a chip label when the most recent send has settled to `.sent`.
    /// Nil otherwise (no chip shown while idle or mid-flight).
    private var sentChipLabel: String? {
        if case .sent = vm.sendStatus { return "Sent ✓" }
        return nil
    }

    // MARK: - Post-sale action row

    private var postSaleActionRow: some View {
        VStack(spacing: BrandSpacing.sm) {
            // Secondary actions
            HStack(spacing: BrandSpacing.sm) {
                secondaryActionButton(
                    label: "View ticket",
                    systemImage: "ticket",
                    identifier: "pos.receipt.viewTicket"
                ) { vm.viewTicket() }

                secondaryActionButton(
                    label: "Customer",
                    systemImage: "person.circle",
                    identifier: "pos.receipt.viewCustomer"
                ) { vm.viewCustomerProfile() }

                secondaryActionButton(
                    label: "Refund",
                    systemImage: "arrow.uturn.backward.circle",
                    identifier: "pos.receipt.startRefund"
                ) { vm.startRefund() }
            }

            // Primary CTA — next sale
            Button {
                vm.nextSale()
                dismiss()
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "arrow.forward.circle.fill")
                    Text("New sale")
                        .font(.brandTitleMedium())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Start new sale")
            .accessibilityHint("Clears the cart and returns to the POS")
            .accessibilityIdentifier("pos.receipt.newSale")
        }
    }

    private func secondaryActionButton(
        label: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(.brandLabelLarge())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .foregroundStyle(.bizarreOnSurface)
        }
        .buttonStyle(.bordered)
        .tint(.bizarreOrange)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

}

// MARK: - Preview

#Preview("Receipt — SMS primary, loyalty tier-up") {
    PosReceiptView(
        vm: PosReceiptViewModel(
            payload: PosReceiptPayload(
                invoiceId: 28014,
                amountPaidCents: 27451,
                changeGivenCents: 2549,
                cashReceivedCents: 30000,
                methodLabel: "Cash",
                customerPhone: "+15558675309",
                customerEmail: "jane@example.com",
                loyaltyDelta: 55,
                loyaltyTierBefore: "Gold",
                loyaltyTierAfter: "Gold",
                loyaltyPointsTotal: 285,
                loyaltyNextTierPoints: 500
            )
        ),
        receiptText: "BizarreCRM Demo\n123 Main St\n\nTotal: $274.51\n\nThank you!",
        paidAt: Date()
    )
    .preferredColorScheme(.dark)
}

#Preview("Receipt — Print primary, no loyalty") {
    PosReceiptView(
        vm: PosReceiptViewModel(
            payload: PosReceiptPayload(
                invoiceId: 99,
                amountPaidCents: 5000,
                methodLabel: "Visa •4242"
            )
        ),
        paidAt: Date()
    )
    .preferredColorScheme(.light)
}
#endif

// MARK: - §16.7 — PDF File Document (FileExporter support)

#if canImport(UIKit)
import UniformTypeIdentifiers

/// Wraps a locally-generated PDF file URL for use with `.fileExporter`.
public struct ReceiptPDFDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.pdf] }

    let url: URL

    public init(url: URL) { self.url = url }

    public init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Data(contentsOf: url)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// ViewModifier that conditionally attaches a `.fileExporter` when a PDF URL
/// is ready. SwiftUI's `.fileExporter` requires a non-Optional document, so
/// we gate on `url != nil` here.
struct ReceiptPDFExporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var url: URL?
    let invoiceId: Int64

    private var filename: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return "Receipt-\(invoiceId)-\(f.string(from: Date())).pdf"
    }

    func body(content: Content) -> some View {
        if let readyURL = url {
            content.fileExporter(
                isPresented: $isPresented,
                document: ReceiptPDFDocument(url: readyURL),
                contentType: .pdf,
                defaultFilename: filename
            ) { result in
                if case .failure(let err) = result {
                    AppLog.pos.error("Receipt PDF export failed: \(err.localizedDescription)")
                }
            }
        } else {
            content
        }
    }
}
#endif
