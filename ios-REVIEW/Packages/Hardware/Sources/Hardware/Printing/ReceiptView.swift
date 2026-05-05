#if canImport(SwiftUI)
import SwiftUI

// MARK: - ReceiptView
//
// Single SwiftUI view that backs ALL receipt output channels:
//   - Thermal printer  → `ImageRenderer(content: ReceiptView(…)) → ESC/POS raster bitmap`
//   - AirPrint / PDF   → `UIGraphicsPDFRenderer` renders the same view
//   - Share sheet      → PDF file URL from above
//   - Email attachment → same PDF
//   - In-app preview   → live `ReceiptView` in a scroll view
//
// The view reads `@Environment(\.printMedium)` so the same source adapts to
// 80mm thermal, 58mm thermal, Letter paper, etc.
//
// Liquid Glass: NOT applied here — receipts are data content, not chrome.

public struct ReceiptView: View {

    // MARK: - Input

    public let model: ReceiptPayload

    // MARK: - Environment

    @Environment(\.printMedium) private var medium

    // MARK: - Init

    public init(model: ReceiptPayload) {
        self.model = model
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            header
            divider
            metaBlock
            divider
            lineItemsBlock
            divider
            totalsBlock
            divider
            tenderBlock
            if let footer = model.footerMessage, !footer.isEmpty {
                footerBlock(footer)
            }
            if let qr = model.qrContent, !qr.isEmpty {
                qrBlock(qr)
            }
            Spacer(minLength: 8)
        }
        .frame(width: medium.contentWidth)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    // MARK: - Header (tenant branding)

    private var header: some View {
        VStack(spacing: 2) {
            Text(model.tenantName)
                .font(medium.headerFont)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(model.tenantAddress)
                .font(medium.bodyFont)
                .multilineTextAlignment(.center)
            Text(model.tenantPhone)
                .font(medium.bodyFont)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Meta block (receipt # / date / cashier)

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("Receipt:")
                    .font(medium.bodyFont)
                Spacer()
                Text(model.receiptNumber)
                    .font(medium.bodyFont)
                    .accessibilityLabel("Receipt number \(model.receiptNumber)")
            }
            HStack {
                Text("Date:")
                    .font(medium.bodyFont)
                Spacer()
                Text(model.createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(medium.bodyFont)
            }
            HStack {
                Text("Cashier:")
                    .font(medium.bodyFont)
                Spacer()
                Text(model.cashierName)
                    .font(medium.bodyFont)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Line items

    private var lineItemsBlock: some View {
        VStack(spacing: 1) {
            ForEach(Array(model.lineItems.enumerated()), id: \.offset) { _, item in
                lineItemRow(label: item.label, value: item.value)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Totals

    private var totalsBlock: some View {
        VStack(spacing: 1) {
            lineItemRow(label: "Subtotal", value: formatCents(model.subtotalCents))
            lineItemRow(label: "Tax", value: formatCents(model.taxCents))
            if model.tipCents > 0 {
                lineItemRow(label: "Tip", value: formatCents(model.tipCents))
            }
            HStack {
                Text("TOTAL")
                    .font(medium.bodyFont.bold())
                Spacer()
                Text(formatCents(model.totalCents))
                    .font(medium.bodyFont.bold())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tender

    private var tenderBlock: some View {
        lineItemRow(label: "Tender", value: model.paymentTender)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private func footerBlock(_ text: String) -> some View {
        VStack {
            divider
            Text(text)
                .font(medium.captionFont)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Footer: \(text)")
    }

    // MARK: - QR code

    private func qrBlock(_ content: String) -> some View {
        Group {
            if let image = generateQRImage(content) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(80, medium.contentWidth - 16),
                           height: min(80, medium.contentWidth - 16))
                    .padding(.vertical, 6)
                    .accessibilityLabel("QR code for receipt lookup")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
            .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func lineItemRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(medium.bodyFont)
            Spacer(minLength: 4)
            Text(value)
                .font(medium.bodyFont)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = abs(cents) / 100
        let pennies = abs(cents) % 100
        let sign = cents < 0 ? "-" : ""
        return "\(sign)$\(dollars).\(String(format: "%02d", pennies))"
    }

    private func generateQRImage(_ content: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = content.data(using: .utf8) ?? Data()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 4
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - GiftReceiptView
//
// Price-hidden variant: line item values replaced with "—" so gift recipients
// cannot see what was paid. The same `ReceiptPayload` is reused; only the
// rendering is different.

public struct GiftReceiptView: View {

    public let model: ReceiptPayload
    @Environment(\.printMedium) private var medium

    public init(model: ReceiptPayload) {
        self.model = model
    }

    public var body: some View {
        ReceiptView(model: redacted)
            .environment(\.printMedium, medium)
    }

    private var redacted: ReceiptPayload {
        let hiddenLines = model.lineItems.map {
            ReceiptPayload.Line(label: $0.label, value: "—")
        }
        return ReceiptPayload(
            tenantName: model.tenantName,
            tenantAddress: model.tenantAddress,
            tenantPhone: model.tenantPhone,
            receiptNumber: model.receiptNumber,
            createdAt: model.createdAt,
            lineItems: hiddenLines,
            subtotalCents: 0,
            taxCents: 0,
            tipCents: 0,
            totalCents: 0,
            paymentTender: "GIFT",
            cashierName: model.cashierName,
            footerMessage: model.footerMessage ?? "Thank you for your gift!",
            qrContent: model.qrContent
        )
    }
}

// MARK: - WorkOrderTicketView
//
// Repair-ticket document: ticket number, customer, device summary, pre-conditions
// checklist placeholder, and signature line. Uses `ReceiptPayload` as the data
// carrier (the line items represent checklist items or notes).

public struct WorkOrderTicketView: View {

    public let model: ReceiptPayload
    /// Optional ticket number override (e.g. "TKT-2024-00123").
    public let ticketNumber: String?
    public let deviceSummary: String?

    @Environment(\.printMedium) private var medium

    public init(
        model: ReceiptPayload,
        ticketNumber: String? = nil,
        deviceSummary: String? = nil
    ) {
        self.model = model
        self.ticketNumber = ticketNumber
        self.deviceSummary = deviceSummary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock
            divider
            ticketInfoBlock
            divider
            if !model.lineItems.isEmpty {
                notesBlock
                divider
            }
            signatureBlock
        }
        .frame(width: medium.contentWidth)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var headerBlock: some View {
        VStack(spacing: 1) {
            Text("WORK ORDER")
                .font(medium.headerFont)
                .accessibilityAddTraits(.isHeader)
            Text(model.tenantName)
                .font(medium.bodyFont)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var ticketInfoBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ticket = ticketNumber {
                labelValue("Ticket:", ticket)
            }
            labelValue("Customer:", model.cashierName) // cashierName doubles as staff ref
            if let device = deviceSummary {
                labelValue("Device:", device)
            }
            labelValue("Date:", model.createdAt.formatted(.dateTime.month().day().year()))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Notes / Pre-conditions")
                .font(medium.bodyFont.bold())
                .padding(.bottom, 2)
            ForEach(Array(model.lineItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top) {
                    Text("□")
                        .font(medium.bodyFont)
                    Text(item.label)
                        .font(medium.bodyFont)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signatureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Customer Signature")
                .font(medium.captionFont)
            Rectangle()
                .stroke(Color.black, lineWidth: 0.5)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            Text("I authorise the work described above.")
                .font(medium.captionFont)
                .foregroundStyle(Color.gray)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
            .padding(.horizontal, 2)
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(medium.bodyFont)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(medium.bodyFont)
        }
    }
}

// MARK: - Previews

#Preview("80mm Receipt") {
    ScrollView {
        ReceiptView(model: .preview)
            .environment(\.printMedium, .thermal80mm)
            .padding()
    }
}

#Preview("Gift Receipt") {
    ScrollView {
        GiftReceiptView(model: .preview)
            .environment(\.printMedium, .thermal80mm)
            .padding()
    }
}

#Preview("Work Order") {
    ScrollView {
        WorkOrderTicketView(
            model: .preview,
            ticketNumber: "TKT-2026-00042",
            deviceSummary: "iPhone 15 Pro — cracked screen"
        )
        .environment(\.printMedium, .thermal80mm)
        .padding()
    }
}

// MARK: - ReceiptPayload preview helper

private extension ReceiptPayload {
    static let preview = ReceiptPayload(
        tenantName: "Bizarre Fix Co.",
        tenantAddress: "456 Elm Street, Springfield",
        tenantPhone: "(555) 123-4567",
        receiptNumber: "REC-2026-00099",
        createdAt: Date(timeIntervalSince1970: 1_750_000_000),
        lineItems: [
            .init(label: "Screen Repair", value: "$79.99"),
            .init(label: "Labor (1hr)",   value: "$45.00"),
            .init(label: "Parts",         value: "$12.50")
        ],
        subtotalCents: 13749,
        taxCents: 1100,
        tipCents: 0,
        totalCents: 14849,
        paymentTender: "Visa ••••1234",
        cashierName: "Alice",
        footerMessage: "Thank you for choosing Bizarre Fix!",
        qrContent: "https://app.bizarrecrm.com/receipts/REC-2026-00099"
    )
}
#endif
