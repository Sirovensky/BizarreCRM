#if canImport(SwiftUI)
import SwiftUI

// MARK: - Document Views
//
// §17.4 "Single ReceiptView per document type":
//   ReceiptView, GiftReceiptView, WorkOrderTicketView — see ReceiptView.swift
//   IntakeFormView, ARStatementView, ZReportView, LabelView — this file
//
// Every view reads `@Environment(\.printMedium)` so the SAME source adapts
// to 80mm thermal, Letter paper, label stock, etc.
// None of these views use Liquid Glass — they are data content, not chrome.

// MARK: - IntakeFormModel

/// Data needed to render a device intake form (pre-conditions + signature).
public struct IntakeFormModel: Sendable {
    public let tenantName: String
    public let ticketNumber: String
    public let customerName: String
    public let deviceSummary: String
    public let receivedAt: Date
    /// Pre-condition items; each is a label that maps to a checkbox.
    public let conditions: [String]
    /// Technician name who received the device.
    public let receivedBy: String

    public init(
        tenantName: String,
        ticketNumber: String,
        customerName: String,
        deviceSummary: String,
        receivedAt: Date,
        conditions: [String] = IntakeFormModel.defaultConditions,
        receivedBy: String
    ) {
        self.tenantName = tenantName
        self.ticketNumber = ticketNumber
        self.customerName = customerName
        self.deviceSummary = deviceSummary
        self.receivedAt = receivedAt
        self.conditions = conditions
        self.receivedBy = receivedBy
    }

    public static let defaultConditions: [String] = [
        "Screen cracked / damaged",
        "Water damage present",
        "Passcode known / provided",
        "Battery swollen",
        "SIM tray present",
        "SD card present",
        "Accessories included",
        "Backup completed",
        "Device powers on"
    ]
}

// MARK: - IntakeFormView

/// Printable device intake form with pre-conditions checklist and customer signature.
///
/// Backs the "Print intake form" action on the ticket detail screen.
public struct IntakeFormView: View {

    public let model: IntakeFormModel
    @Environment(\.printMedium) private var medium

    public init(model: IntakeFormModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            metaBlock
            divider
            conditionsBlock
            divider
            signatureBlock
        }
        .frame(width: medium.contentWidth)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("DEVICE INTAKE FORM")
                .font(medium.headerFont)
                .accessibilityAddTraits(.isHeader)
            Text(model.tenantName)
                .font(medium.bodyFont)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            labelValue("Ticket #:", model.ticketNumber)
            labelValue("Customer:", model.customerName)
            labelValue("Device:", model.deviceSummary)
            labelValue("Date:", model.receivedAt.formatted(.dateTime.month().day().year()))
            labelValue("Received by:", model.receivedBy)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conditionsBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Pre-Condition Checklist")
                .font(medium.bodyFont.bold())
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            Text("(Tech initials each checked item)")
                .font(medium.captionFont)
                .foregroundStyle(Color.gray)
                .padding(.bottom, 2)
            ForEach(Array(model.conditions.enumerated()), id: \.offset) { _, condition in
                HStack(alignment: .top, spacing: 4) {
                    Text("□")
                        .font(medium.bodyFont)
                        .accessibilityHidden(true)
                    Text(condition)
                        .font(medium.bodyFont)
                    Spacer()
                    Text("____")
                        .font(medium.captionFont)
                        .foregroundStyle(Color.gray)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signatureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Customer Acknowledgement")
                .font(medium.bodyFont.bold())
                .accessibilityAddTraits(.isHeader)
            Text("By signing, I confirm the above conditions accurately reflect the device state at drop-off.")
                .font(medium.captionFont)
                .foregroundStyle(Color.gray)
            HStack(alignment: .bottom, spacing: 4) {
                Text("Signature:")
                    .font(medium.bodyFont)
                Rectangle()
                    .stroke(Color.black, lineWidth: 0.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
            }
            .padding(.top, 4)
            HStack(alignment: .bottom, spacing: 4) {
                Text("Date:")
                    .font(medium.bodyFont)
                Rectangle()
                    .stroke(Color.black, lineWidth: 0.5)
                    .frame(width: 80)
                    .frame(height: 14)
            }
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
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(medium.bodyFont)
        }
    }
}

// MARK: - ARStatementModel

/// Data for an A/R (accounts-receivable) statement.
public struct ARStatementModel: Sendable {
    public let tenantName: String
    public let tenantAddress: String
    public let customerName: String
    public let customerAddress: String?
    public let statementDate: Date
    public let periodStart: Date
    public let periodEnd: Date
    public struct LineItem: Sendable {
        public let date: Date
        public let invoiceNumber: String
        public let description: String
        public let amountCents: Int
        public let paidCents: Int
        public init(date: Date, invoiceNumber: String, description: String, amountCents: Int, paidCents: Int) {
            self.date = date
            self.invoiceNumber = invoiceNumber
            self.description = description
            self.amountCents = amountCents
            self.paidCents = paidCents
        }
        public var balanceCents: Int { amountCents - paidCents }
    }
    public let lineItems: [LineItem]
    public var totalBalanceCents: Int { lineItems.reduce(0) { $0 + $1.balanceCents } }

    public init(
        tenantName: String,
        tenantAddress: String,
        customerName: String,
        customerAddress: String?,
        statementDate: Date,
        periodStart: Date,
        periodEnd: Date,
        lineItems: [LineItem]
    ) {
        self.tenantName = tenantName
        self.tenantAddress = tenantAddress
        self.customerName = customerName
        self.customerAddress = customerAddress
        self.statementDate = statementDate
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.lineItems = lineItems
    }
}

// MARK: - ARStatementView

/// Printable accounts-receivable statement (Letter / A4 preferred; thermal fallback).
public struct ARStatementView: View {

    public let model: ARStatementModel
    @Environment(\.printMedium) private var medium

    public init(model: ARStatementModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            addressBlock
            divider
            itemsBlock
            divider
            totalsBlock
        }
        .frame(width: medium.contentWidth)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACCOUNT STATEMENT")
                    .font(medium.headerFont)
                    .accessibilityAddTraits(.isHeader)
                Text(model.tenantName)
                    .font(medium.bodyFont)
                Text(model.tenantAddress)
                    .font(medium.captionFont)
                    .foregroundStyle(Color.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Statement Date")
                    .font(medium.captionFont)
                    .foregroundStyle(Color.gray)
                Text(model.statementDate.formatted(.dateTime.month().day().year()))
                    .font(medium.bodyFont)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    private var addressBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Bill To:").font(medium.captionFont).foregroundStyle(Color.gray)
            Text(model.customerName).font(medium.bodyFont)
            if let addr = model.customerAddress {
                Text(addr).font(medium.captionFont).foregroundStyle(Color.gray)
            }
            HStack {
                Text("Period:")
                    .font(medium.captionFont).foregroundStyle(Color.gray)
                Text("\(model.periodStart.formatted(.dateTime.month().day().year())) – \(model.periodEnd.formatted(.dateTime.month().day().year()))")
                    .font(medium.captionFont)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var itemsBlock: some View {
        VStack(spacing: 1) {
            // Header row
            HStack {
                Text("Date").font(medium.captionFont.bold()).frame(width: 52, alignment: .leading)
                Text("Invoice").font(medium.captionFont.bold()).frame(width: 56, alignment: .leading)
                Text("Description").font(medium.captionFont.bold()).frame(maxWidth: .infinity, alignment: .leading)
                Text("Balance").font(medium.captionFont.bold()).frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
            ForEach(Array(model.lineItems.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.date.formatted(.dateTime.month().day()))
                        .font(medium.captionFont).frame(width: 52, alignment: .leading)
                    Text(item.invoiceNumber)
                        .font(medium.captionFont).frame(width: 56, alignment: .leading)
                    Text(item.description)
                        .font(medium.captionFont).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatCents(item.balanceCents))
                        .font(medium.captionFont)
                        .foregroundStyle(item.balanceCents > 0 ? Color.black : Color.gray)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var totalsBlock: some View {
        HStack {
            Text("BALANCE DUE")
                .font(medium.bodyFont.bold())
            Spacer()
            Text(formatCents(model.totalBalanceCents))
                .font(medium.bodyFont.bold())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
            .padding(.horizontal, 2)
    }

    private func formatCents(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        return "\(sign)$\(abs(cents) / 100).\(String(format: "%02d", abs(cents) % 100))"
    }
}

// MARK: - ZReportModel

/// Data for an end-of-day Z-report (cash register close).
public struct ZReportModel: Sendable {
    public let tenantName: String
    public let locationName: String
    public let cashierName: String
    public let shiftStart: Date
    public let shiftEnd: Date
    public let cashSalesTotalCents: Int
    public let cardSalesTotalCents: Int
    public let refundsTotalCents: Int
    public let drawerOpenings: Int
    public let receiptCount: Int
    public let cashInDrawerCents: Int
    public let expectedCashCents: Int

    public var overShortCents: Int { cashInDrawerCents - expectedCashCents }

    public init(
        tenantName: String,
        locationName: String,
        cashierName: String,
        shiftStart: Date,
        shiftEnd: Date,
        cashSalesTotalCents: Int,
        cardSalesTotalCents: Int,
        refundsTotalCents: Int,
        drawerOpenings: Int,
        receiptCount: Int,
        cashInDrawerCents: Int,
        expectedCashCents: Int
    ) {
        self.tenantName = tenantName
        self.locationName = locationName
        self.cashierName = cashierName
        self.shiftStart = shiftStart
        self.shiftEnd = shiftEnd
        self.cashSalesTotalCents = cashSalesTotalCents
        self.cardSalesTotalCents = cardSalesTotalCents
        self.refundsTotalCents = refundsTotalCents
        self.drawerOpenings = drawerOpenings
        self.receiptCount = receiptCount
        self.cashInDrawerCents = cashInDrawerCents
        self.expectedCashCents = expectedCashCents
    }
}

// MARK: - ZReportView

/// End-of-day Z-report document (thermal or paper).
public struct ZReportView: View {

    public let model: ZReportModel
    @Environment(\.printMedium) private var medium

    public init(model: ZReportModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            divider
            shiftBlock
            divider
            salesBlock
            divider
            drawerBlock
            Spacer(minLength: 8)
        }
        .frame(width: medium.contentWidth)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Z-REPORT")
                .font(medium.headerFont)
                .accessibilityAddTraits(.isHeader)
            Text(model.tenantName)
                .font(medium.bodyFont)
            Text(model.locationName)
                .font(medium.captionFont)
                .foregroundStyle(Color.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var shiftBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Cashier:", model.cashierName)
            row("Shift Start:", model.shiftStart.formatted(.dateTime.month().day().year().hour().minute()))
            row("Shift End:", model.shiftEnd.formatted(.dateTime.month().day().year().hour().minute()))
            row("Receipts:", "\(model.receiptCount)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var salesBlock: some View {
        VStack(spacing: 1) {
            row("Cash Sales:", formatCents(model.cashSalesTotalCents))
            row("Card Sales:", formatCents(model.cardSalesTotalCents))
            row("Refunds:", "-\(formatCents(model.refundsTotalCents))")
            HStack {
                Text("NET SALES:")
                    .font(medium.bodyFont.bold())
                Spacer()
                let net = model.cashSalesTotalCents + model.cardSalesTotalCents - model.refundsTotalCents
                Text(formatCents(net))
                    .font(medium.bodyFont.bold())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    private var drawerBlock: some View {
        VStack(spacing: 1) {
            row("Drawer Openings:", "\(model.drawerOpenings)")
            row("Expected Cash:", formatCents(model.expectedCashCents))
            row("Actual Cash:", formatCents(model.cashInDrawerCents))
            HStack {
                Text(model.overShortCents >= 0 ? "OVER:" : "SHORT:")
                    .font(medium.bodyFont.bold())
                Spacer()
                Text(formatCents(abs(model.overShortCents)))
                    .font(medium.bodyFont.bold())
                    .foregroundStyle(model.overShortCents == 0 ? Color.black : Color.black)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(medium.bodyFont)
            Spacer()
            Text(value).font(medium.bodyFont)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
            .padding(.horizontal, 2)
    }

    private func formatCents(_ cents: Int) -> String {
        "$\(cents / 100).\(String(format: "%02d", cents % 100))"
    }
}

// MARK: - LabelModel

/// Data for a shelf-tag / product label.
public struct LabelModel: Sendable {
    public let productName: String
    public let sku: String?
    public let retailPrice: Double
    public let barcode: String?
    public let barcodeFormat: String  // "code128", "ean13", etc.

    public init(
        productName: String,
        sku: String?,
        retailPrice: Double,
        barcode: String?,
        barcodeFormat: String = "code128"
    ) {
        self.productName = productName
        self.sku = sku
        self.retailPrice = retailPrice
        self.barcode = barcode
        self.barcodeFormat = barcodeFormat
    }
}

// MARK: - LabelView

/// Shelf / product label view. Adapts to label media via `@Environment(\.printMedium)`.
///
/// For small labels (2×1, 2×4) the layout collapses to essentials:
/// product name + price. Larger labels add SKU + barcode.
public struct LabelView: View {

    public let model: LabelModel
    @Environment(\.printMedium) private var medium

    public init(model: LabelModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(model.productName)
                .font(medium.headerFont)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            Text(formatPrice(model.retailPrice))
                .font(medium.bodyFont.bold())
                .foregroundStyle(Color.black)

            if medium != .label2x4, let sku = model.sku, !sku.isEmpty {
                Text("SKU: \(sku)")
                    .font(medium.captionFont)
                    .foregroundStyle(Color.gray)
            }

            if let bc = model.barcode, !bc.isEmpty,
               medium == .label4x6 || medium == .letter || medium == .a4 {
                barcodeImage(bc)
                    .frame(height: 40)
            }
        }
        .padding(4)
        .frame(width: medium.contentWidth)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    @ViewBuilder
    private func barcodeImage(_ code: String) -> some View {
        if let img = generateCode128(code) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Barcode for \(model.productName)")
        }
    }

    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }

    /// Generates a Code 128 barcode image via CIFilter.
    private func generateCode128(_ code: String) -> UIImage? {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        guard let data = code.data(using: .ascii) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(2.0, forKey: "inputQuietSpace")
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 3
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Intake Form") {
    ScrollView {
        IntakeFormView(model: IntakeFormModel(
            tenantName: "Bizarre Fix Co.",
            ticketNumber: "TKT-2026-00042",
            customerName: "Jane Smith",
            deviceSummary: "iPhone 15 Pro — cracked screen",
            receivedAt: Date(),
            receivedBy: "Alice"
        ))
        .environment(\.printMedium, .thermal80mm)
        .padding()
    }
}

#Preview("A/R Statement") {
    ScrollView {
        ARStatementView(model: ARStatementModel(
            tenantName: "Bizarre Fix Co.",
            tenantAddress: "456 Elm Street",
            customerName: "ABC Corp.",
            customerAddress: nil,
            statementDate: Date(),
            periodStart: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
            periodEnd: Date(),
            lineItems: [
                .init(date: Date(), invoiceNumber: "INV-001", description: "Screen repair", amountCents: 9999, paidCents: 0)
            ]
        ))
        .environment(\.printMedium, .letter)
        .padding()
    }
}

#Preview("Z-Report") {
    ScrollView {
        ZReportView(model: ZReportModel(
            tenantName: "Bizarre Fix Co.",
            locationName: "Main Street",
            cashierName: "Alice",
            shiftStart: Calendar.current.date(byAdding: .hour, value: -8, to: Date())!,
            shiftEnd: Date(),
            cashSalesTotalCents: 45000,
            cardSalesTotalCents: 123000,
            refundsTotalCents: 2500,
            drawerOpenings: 12,
            receiptCount: 34,
            cashInDrawerCents: 42600,
            expectedCashCents: 42500
        ))
        .environment(\.printMedium, .thermal80mm)
        .padding()
    }
}

#Preview("Label") {
    LabelView(model: LabelModel(
        productName: "USB-C Cable 6ft",
        sku: "CAB-USBC-6",
        retailPrice: 19.99,
        barcode: "850026102152"
    ))
    .environment(\.printMedium, .label4x6)
    .padding()
}
#endif

#endif
