#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosReturnReceiptView (§16.9)

/// Receipt screen displayed after a return / refund is processed.
///
/// Differences from a regular sale receipt:
/// - "RETURN" watermark (red badge) in the header — mandatory per §16.9.
/// - Shows refund amount (negative dollars), original invoice reference,
///   and the tender method used for the refund.
/// - Signature section if the refund exceeded the manager-PIN threshold and
///   a signature was captured (e.g. via `PKCanvasView` on-screen).
///
/// iPhone: full-screen receipt in a `NavigationStack` sheet.
/// iPad: fixed 480 pt width centred panel.
///
/// Wired from `PosReturnDetailView` after `.sent` status is received.
public struct PosReturnReceiptView: View {

    // MARK: - Model

    public struct ReturnReceiptPayload: Sendable {
        public let returnId: String             // Server-assigned or client UUID
        public let originalInvoiceId: String    // "#00042"
        public let customerName: String
        public let lines: [ReturnReceiptLine]
        public let refundTender: RefundTender
        public let refundAmountCents: Int
        public let signatureData: Data?         // PKDrawing bytes, or nil
        public let processedAt: Date

        public init(
            returnId: String,
            originalInvoiceId: String,
            customerName: String,
            lines: [ReturnReceiptLine],
            refundTender: RefundTender,
            refundAmountCents: Int,
            signatureData: Data? = nil,
            processedAt: Date = .now
        ) {
            self.returnId = returnId
            self.originalInvoiceId = originalInvoiceId
            self.customerName = customerName
            self.lines = lines
            self.refundTender = refundTender
            self.refundAmountCents = refundAmountCents
            self.signatureData = signatureData
            self.processedAt = processedAt
        }
    }

    public struct ReturnReceiptLine: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let quantity: Int
        public let unitPriceCents: Int

        public init(id: UUID = UUID(), name: String, quantity: Int, unitPriceCents: Int) {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.unitPriceCents = unitPriceCents
        }
    }

    public enum RefundTender: Sendable {
        case cash
        case storeCredit
        case giftCard(code: String)
        case originalCard(last4: String)

        var displayLabel: String {
            switch self {
            case .cash:                     return "Cash"
            case .storeCredit:              return "Store credit"
            case .giftCard(let code):       return "Gift card ···\(code.suffix(4))"
            case .originalCard(let last4):  return "Card ···\(last4)"
            }
        }
    }

    // MARK: - State

    let payload: PosReturnReceiptView.ReturnReceiptPayload
    let onPrint: (() -> Void)?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    public init(
        payload: PosReturnReceiptView.ReturnReceiptPayload,
        onPrint: (() -> Void)? = nil,
        onDone: @escaping () -> Void
    ) {
        self.payload = payload
        self.onPrint = onPrint
        self.onDone = onDone
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    ScrollView { receiptContent.padding() }
                } else {
                    ScrollView {
                        receiptContent
                            .padding()
                            .frame(maxWidth: 480)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Return Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
    }

    // MARK: - Receipt body

    @ViewBuilder
    private var receiptContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            returnHeader
            Divider().background(Color.bizarreOutline)
            lineItems
            Divider().background(Color.bizarreOutline)
            tenderRow
            if let sigData = payload.signatureData {
                Divider().background(Color.bizarreOutline)
                signatureSection(data: sigData)
            }
            footerNote
        }
        .padding(BrandSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(Color.bizarreSurface)
        )
    }

    // MARK: - Header with RETURN badge

    private var returnHeader: some View {
        VStack(alignment: .center, spacing: BrandSpacing.md) {
            // RETURN badge — mandatory per §16.9
            Text("RETURN")
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.vertical, BrandSpacing.xs)
                .background(
                    Capsule()
                        .fill(BrandPalette.error)
                )
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("pos.returnReceipt.badge")

            Text("Return #\(payload.returnId)")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityIdentifier("pos.returnReceipt.returnId")

            Text("Original: \(payload.originalInvoiceId)")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Text(payload.customerName)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)

            Text(payload.processedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Line items

    @ViewBuilder
    private var lineItems: some View {
        VStack(spacing: BrandSpacing.xs) {
            ForEach(payload.lines) { line in
                HStack(alignment: .top) {
                    Text("\(line.quantity)× \(line.name)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("-\(CartMath.formatCents(line.unitPriceCents * line.quantity))")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(line.quantity) \(line.name), minus \(CartMath.formatCents(line.unitPriceCents * line.quantity))")
            }
        }
    }

    // MARK: - Tender / refund amount

    private var tenderRow: some View {
        VStack(spacing: BrandSpacing.sm) {
            HStack {
                Text("Refund total")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text("-\(CartMath.formatCents(payload.refundAmountCents))")
                    .font(.brandDisplaySmall())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
            }
            HStack {
                Text("Via")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(payload.refundTender.displayLabel)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Refund of \(CartMath.formatCents(payload.refundAmountCents)) via \(payload.refundTender.displayLabel)")
        .accessibilityIdentifier("pos.returnReceipt.total")
    }

    // MARK: - Signature

    private func signatureSection(data: Data) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Signature")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 80)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Customer signature")
                    .accessibilityIdentifier("pos.returnReceipt.signature")
            } else {
                // Fallback: show a placeholder when signature can't be decoded
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.bizarreOutline.opacity(0.3))
                    .frame(height: 60)
                    .overlay {
                        Text("Signature on file")
                            .font(.brandBodySmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
            }
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Thank you. Contact us with questions about your return.")
            .font(.brandBodySmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("pos.returnReceipt.footer")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if let print = onPrint {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    print()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .accessibilityIdentifier("pos.returnReceipt.print")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                onDone()
                dismiss()
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("pos.returnReceipt.done")
        }
    }
}

// MARK: - Convenience colour alias

private extension BrandPalette {
    static var error: Color { Color(hex: "#e2526c") }
}
#endif
