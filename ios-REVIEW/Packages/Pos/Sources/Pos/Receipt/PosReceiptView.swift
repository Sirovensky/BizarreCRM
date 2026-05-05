#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import CoreImage
import CoreImage.CIFilterBuiltins

/// §Agent-E / §16.24 — Receipt confirmation screen. Shown immediately after a
/// tender settles. Replaces (sits alongside) `PosPostSaleView` — the older view
/// is retained for the spinner/phase transition; this view is the settled state.
///
/// §16.24 additions:
/// - Hero circle with 600ms spring scale animation.
/// - "SEND RECEIPT" vertical rows (SMS disabled POS-SMS-001, email enabled,
///   thermal print disabled until §17).
/// - Teal "Parts reserved to Ticket #N" row when `linkedRepairTicketId` is set.
/// - Auto-dismiss 10s countdown ("Starting new sale in Ns…") that fires
///   `vm.nextSale()` when it reaches 0. Any tap cancels it.
/// - "Open ticket #N" secondary CTA when repair ticket is linked.
///
/// Layout (iPhone + iPad share the same scroll body; iPad gets the collapse
/// modifier on the cart column via the parent):
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │  SUCCESS HERO  (check + spring + amount)│
/// ├─────────────────────────────────────────┤
/// │  TICKET LINK ROW (teal, if linked)      │
/// ├─────────────────────────────────────────┤
/// │  SEND RECEIPT rows                      │
/// ├─────────────────────────────────────────┤
/// │  QR CODE                                │
/// ├─────────────────────────────────────────┤
/// │  LOYALTY CELEBRATION ROW (if pts > 0)   │
/// ├─────────────────────────────────────────┤
/// │  RECEIPT PREVIEW (monospace, scrollable)│
/// ├─────────────────────────────────────────┤
/// │  NEXT-ACTION CTA BAR (glass background) │
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
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var showingPdfExporter: Bool = false
    @State private var pdfExportURL: URL?
    @State private var heroScale: CGFloat = 0.82
    @State private var heroOpacity: Double = 0
    @State private var showingReceiptPreview: Bool = false

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
            if hSizeClass == .regular {
                iPadBody
            } else {
                scrollBody
            }
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
            // §16.24 — Trigger hero spring animation then start auto-dismiss.
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                heroScale = 1.0
                heroOpacity = 1.0
            }
            vm.startAutoDismissCountdown()
        }
        // Cancel auto-dismiss on any tap.
        .simultaneousGesture(
            TapGesture().onEnded { vm.cancelAutoDismiss() }
        )
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

    // MARK: - iPad 2-column layout (screen 5)
    //
    // Left: hero (highest elevation) → share tiles → loyalty → actions → pencil banner
    // Right: receipt preview (lowest elevation, supporting context)

    private var iPadBody: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    Spacer(minLength: BrandSpacing.lg)
                    heroSection
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        Text("Send receipt")
                            .font(.brandLabelSmall().weight(.semibold))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        shareTileGrid
                    }
                    loyaltyCelebration
                    postSaleActionRow
                    // Pencil signature banner — shown only when a signed ticket
                    // exists AND we're on iPad regular size class (per spec item 5).
                    if let ticketId = vm.payload.signedTicketId {
                        pencilSignatureBanner(ticketId: ticketId)
                    }
                    Spacer(minLength: BrandSpacing.xl)
                }
                .padding(.horizontal, BrandSpacing.lg)
            }
            .frame(maxWidth: .infinity)

            // Vertical divider
            Rectangle()
                .fill(Color.bizarreOutline.opacity(0.35))
                .frame(width: 1)

            // Right column — receipt preview
            if let text = receiptText {
                ScrollView {
                    VStack(spacing: BrandSpacing.md) {
                        Spacer(minLength: BrandSpacing.lg)
                        PosReceiptListPreview(receiptText: text)
                            .padding(.horizontal, BrandSpacing.base)
                        Spacer(minLength: BrandSpacing.xl)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Scroll body (iPhone + iPad fallback)

    private var scrollBody: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                Spacer(minLength: BrandSpacing.xl)
                heroSection
                shareTileGrid
                loyaltyCelebration
                // Pencil signature banner — gated on signedTicketId != nil
                // AND iPad regular size class only (mockup screen 5).
                if let ticketId = vm.payload.signedTicketId, hSizeClass == .regular {
                    pencilSignatureBanner(ticketId: ticketId)
                }
                if receiptText != nil {
                    receiptPreviewToggle
                }
                postSaleActionRow
                // Note: Pencil signature banner is iPad-only (spec item 5).
                // It appears in the iPadBody left column, not here.
                Spacer(minLength: BrandSpacing.xl)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Pencil signature banner

    private func pencilSignatureBanner(ticketId: Int64) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 22))
                .foregroundStyle(.bizarreTeal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Signature captured with Pencil")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Archived to ticket #\(ticketId)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreTeal.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pencil signature captured and archived to ticket \(ticketId)")
        .accessibilityIdentifier("pos.receipt.pencilSignatureBanner")
    }

    // MARK: - Hero

    private var iPhoneLayout: some View {
        VStack(spacing: BrandSpacing.lg) {
            heroSection
            ticketLinkRow
            sendReceiptSection
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
            // Left: hero + ticket link + send receipt + loyalty + pencil banner + post-sale actions
            VStack(spacing: BrandSpacing.lg) {
                heroSection
                ticketLinkRow
                sendReceiptSection
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

    // MARK: - §16.24 — Ticket link row

    /// Teal row: "Parts reserved to Ticket #NNNN" — shown when a repair ticket
    /// is linked to this sale. Matches §16.24 spec hero sub-row.
    @ViewBuilder
    private var ticketLinkRow: some View {
        if let ticketId = vm.payload.linkedRepairTicketId {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.bizarreTeal)
                    .accessibilityHidden(true)
                Text("Parts reserved to Ticket #\(ticketId)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.bizarreTeal)
                Spacer()
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(Color.bizarreTeal.opacity(0.30), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Parts reserved to Ticket \(ticketId)")
            .accessibilityIdentifier("pos.receipt.ticketLink")
        }
    }

    // MARK: - §16.24 — SEND RECEIPT section

    /// Vertical list of send-receipt rows per §16.24 spec.
    /// SMS: disabled (POS-SMS-001 pending).
    /// Email: enabled when customer email on file.
    /// Thermal print: disabled until §17.
    private var sendReceiptSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            // Section label
            Text("SEND RECEIPT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .kerning(1.0)
                .padding(.horizontal, BrandSpacing.sm)

            VStack(spacing: 0) {
                // SMS row — disabled POS-SMS-001
                sendReceiptRow(
                    icon: "message.fill",
                    label: "SMS",
                    sublabel: vm.payload.customerPhone ?? "No phone on file",
                    badge: "POS-SMS-001",
                    isPrimary: vm.defaultChannel == .sms,
                    isEnabled: false,
                    identifier: "pos.receipt.send.sms"
                ) {
                    vm.share(channel: .sms)
                }

                Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.md)

                // Email row — enabled
                sendReceiptRow(
                    icon: "envelope.fill",
                    label: "Email",
                    sublabel: vm.payload.customerEmail ?? "No email on file",
                    badge: nil,
                    isPrimary: vm.defaultChannel == .email,
                    isEnabled: vm.payload.customerEmail != nil,
                    identifier: "pos.receipt.send.email"
                ) {
                    vm.share(channel: .email)
                }

                Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.md)

                // Thermal print row — disabled until §17
                sendReceiptRow(
                    icon: "printer.fill",
                    label: "Thermal print",
                    sublabel: "Printer SDK — §17",
                    badge: nil,
                    isPrimary: vm.defaultChannel == .print,
                    isEnabled: false,
                    identifier: "pos.receipt.send.thermalPrint"
                ) {}
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )

            // Send status feedback
            if vm.sendStatus != .idle {
                sendStatusBanner
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.top, BrandSpacing.xs)
            }
        }
    }

    private func sendReceiptRow(
        icon: String,
        label: String,
        sublabel: String,
        badge: String?,
        isPrimary: Bool,
        isEnabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isEnabled ? (isPrimary ? Color.bizarreOrange : Color.bizarreOnSurface) : Color.bizarreOnSurfaceMuted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BrandSpacing.xs) {
                        Text(label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isEnabled ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.bizarreSurface2, in: Capsule())
                        }
                    }
                    Text(sublabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                Spacer()
                if isPrimary && isEnabled {
                    Circle()
                        .fill(Color.bizarreOrange)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                if vm.sendStatus == .sending && isPrimary {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm + 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - §16.24 — Auto-dismiss countdown label

    @ViewBuilder
    private var autoDismissCountdownLabel: some View {
        if let remaining = vm.autoDismissSecondsRemaining {
            Text("Starting new sale in \(remaining)s…")
                .font(.system(size: 12))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Auto-dismiss in \(remaining) seconds. Tap to cancel.")
                .accessibilityIdentifier("pos.receipt.autoDismissCountdown")
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
        if hSizeClass == .regular, let ticketId = vm.payload.signedTicketId {
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

    // MARK: - Offline watermark

    @ViewBuilder
    private var offlineWatermark: some View {
        if vm.payload.isOfflinePending {
            Text("Offline sale queued")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreWarning)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreWarning.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreWarning.opacity(0.35), lineWidth: 1))
                .accessibilityIdentifier("pos.receipt.offlineWatermark")
        }
    }

    // MARK: - §16.24 Hero (spring animated)

    /// Celebration hero — highest visual elevation per mockup spec.
    /// §16.24: 72pt success circle, white checkmark, 600ms spring scale-in.
    /// Below: total in Barlow Condensed (22pt bold), invoice # + customer name (12pt muted).
    private var heroSection: some View {
        VStack(spacing: BrandSpacing.md) {
            // §16.24 — 72pt success circle with white checkmark, spring animated
            ZStack {
                RadialGradient(
                    colors: [Color.bizarreSuccess.opacity(0.35), .clear],
                    center: .center,
                    startRadius: 24,
                    endRadius: 80
                )
                .frame(width: 160, height: 160)
                .accessibilityHidden(true)

                Circle()
                    .fill(Color.bizarreSuccess)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)

                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.white)
                    .accessibilityHidden(true)
            }
            .scaleEffect(heroScale)
            .opacity(heroOpacity)

            // "Payment complete" label
            Text("Payment complete")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("pos.receipt.completionLabel")

            // §16.24 — Amount: Barlow Condensed, 22pt weight-800 equivalent, Dynamic Type capped
            Text(CartMath.formatCents(vm.payload.amountPaidCents))
                .font(
                    .custom("BarlowCondensed-ExtraBold", size: 60, relativeTo: .largeTitle)
                    .leading(.tight)
                )
                .dynamicTypeSize(.large ... .accessibility2)
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityLabel("Amount charged: \(CartMath.formatCents(vm.payload.amountPaidCents))")
                .accessibilityIdentifier("pos.receipt.amount")

            // §16.24 — Invoice number + method (12pt muted)
            Text("Invoice #\(vm.payload.invoiceId) · \(cashDetailLabel)")
                .font(.system(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pos.receipt.methodLabel")

            // §16.12 — OFFLINE watermark (visible until sale syncs)
            offlineWatermark
        }
        .padding(.vertical, BrandSpacing.xl)
        .padding(.horizontal, BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
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

    @ViewBuilder
    private var receiptPreviewToggle: some View {
        if let text = receiptText {
            DisclosureGroup(isExpanded: $showingReceiptPreview) {
                inlineReceiptPreview(text: text)
                    .padding(.top, BrandSpacing.sm)
            } label: {
                Label("Receipt preview", systemImage: "doc.text.magnifyingglass")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
            .accessibilityIdentifier("pos.receipt.previewToggle")
        }
    }

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

    // MARK: - §16.24 Post-sale action row (glass CTA bar)

    private var postSaleActionRow: some View {
        VStack(spacing: BrandSpacing.sm) {
            // §16.24 — Auto-dismiss countdown (muted, above buttons)
            autoDismissCountdownLabel

            // Secondary actions
            HStack(spacing: BrandSpacing.sm) {
                // §16.24 — "Open ticket #N" when repair ticket linked
                if let ticketId = vm.payload.linkedRepairTicketId {
                    secondaryActionButton(
                        label: "Open ticket #\(ticketId)",
                        systemImage: "wrench.and.screwdriver",
                        identifier: "pos.receipt.openTicket"
                    ) { vm.viewTicket() }
                }

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

            // §16.24 — Primary CTA: "New sale ↗" (cream/orange, glass background)
            Button {
                vm.nextSale()
                dismiss()
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "arrow.forward.circle.fill")
                    Text("New sale ↗")
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
        .padding(BrandSpacing.md)
        // §16.24 — Glass background on the CTA bar (chrome role per Liquid Glass rules)
        .background(Color.bizarreSurfaceBase.opacity(0.85))
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
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
