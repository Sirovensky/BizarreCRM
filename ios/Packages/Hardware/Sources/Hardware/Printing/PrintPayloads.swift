import Foundation

// MARK: - Receipt Payload

/// Full data needed to render a receipt on-device. Model is self-contained:
/// every value required by the renderer is embedded (including `logoData` as
/// raw PNG/JPEG bytes), so printing works fully offline with zero deferred
/// network reads inside the render pipeline. §17.4 compliance.
public struct ReceiptPayload: Sendable, Codable {
    public struct Line: Sendable, Codable {
        public let label: String
        public let value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    /// Business logo as raw image bytes (PNG or JPEG).
    /// `nil` → no logo rendered. Never a URL — must be pre-fetched and embedded
    /// before constructing the payload so the renderer stays offline-capable.
    public let logoData: Data?
    public let tenantName: String
    public let tenantAddress: String
    public let tenantPhone: String
    public let receiptNumber: String
    public let createdAt: Date
    public let lineItems: [Line]
    public let subtotalCents: Int
    public let taxCents: Int
    public let tipCents: Int
    public let totalCents: Int
    public let paymentTender: String
    /// Auth code / last-4 from payment terminal. Stored as a token; raw PAN never stored.
    public let paymentAuthLast4: String?
    public let cashierName: String
    public let footerMessage: String?
    public let qrContent: String?

    public init(
        logoData: Data? = nil,
        tenantName: String,
        tenantAddress: String,
        tenantPhone: String,
        receiptNumber: String,
        createdAt: Date,
        lineItems: [Line],
        subtotalCents: Int,
        taxCents: Int,
        tipCents: Int,
        totalCents: Int,
        paymentTender: String,
        paymentAuthLast4: String? = nil,
        cashierName: String,
        footerMessage: String? = nil,
        qrContent: String? = nil
    ) {
        self.logoData = logoData
        self.tenantName = tenantName
        self.tenantAddress = tenantAddress
        self.tenantPhone = tenantPhone
        self.receiptNumber = receiptNumber
        self.createdAt = createdAt
        self.lineItems = lineItems
        self.subtotalCents = subtotalCents
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.totalCents = totalCents
        self.paymentTender = paymentTender
        self.paymentAuthLast4 = paymentAuthLast4
        self.cashierName = cashierName
        self.footerMessage = footerMessage
        self.qrContent = qrContent
    }
}

// MARK: - Label Payload

public enum LabelSize: String, Codable, Sendable, CaseIterable {
    case small_2x1   // 2" × 1"
    case medium_2x3  // 2" × 3"
    case large_4x6   // 4" × 6"

    /// Points at 72 dpi
    public var pointSize: CGSize {
        switch self {
        case .small_2x1:  return CGSize(width: 144, height: 72)
        case .medium_2x3: return CGSize(width: 144, height: 216)
        case .large_4x6:  return CGSize(width: 288, height: 432)
        }
    }
}

public struct LabelPayload: Sendable, Codable {
    public let ticketNumber: String
    public let customerName: String
    public let deviceSummary: String
    public let dateReceived: Date
    public let qrContent: String
    public let size: LabelSize

    public init(
        ticketNumber: String,
        customerName: String,
        deviceSummary: String,
        dateReceived: Date,
        qrContent: String,
        size: LabelSize
    ) {
        self.ticketNumber = ticketNumber
        self.customerName = customerName
        self.deviceSummary = deviceSummary
        self.dateReceived = dateReceived
        self.qrContent = qrContent
        self.size = size
    }
}

// MARK: - Ticket Tag Payload

public struct TicketTagPayload: Sendable, Codable {
    public let ticketNumber: String
    public let customerName: String
    public let deviceModel: String
    public let promisedBy: Date?
    public let qrContent: String

    public init(
        ticketNumber: String,
        customerName: String,
        deviceModel: String,
        promisedBy: Date?,
        qrContent: String
    ) {
        self.ticketNumber = ticketNumber
        self.customerName = customerName
        self.deviceModel = deviceModel
        self.promisedBy = promisedBy
        self.qrContent = qrContent
    }
}

// MARK: - Barcode Payload

public enum BarcodeFormat: String, Codable, Sendable {
    case code128
    case upca
    case ean13
    case qr
}

public struct BarcodePayload: Sendable, Codable {
    public let code: String
    public let format: BarcodeFormat

    public init(code: String, format: BarcodeFormat) {
        self.code = code
        self.format = format
    }
}

// MARK: - PrintDocumentType
//
// §17 "Doc types" — inventory of every printable document type the app supports.
//
// Matching between doc type and print medium:
//   • thermal80mm / thermal58mm  → receipt, giftReceipt, refundReceipt, zReport
//   • letter / a4 / legal        → invoice, quote, workOrder, waiver, laborCertificate,
//                                   arStatement, taxSummary, zReport
//   • label2x4 / label2x1 / etc  → ticketTag (small bag tag)
//
// All doc types are rendered fully on-device from local model data. None use
// a URL-based pipeline (§17.4 lesson from Android regression).

/// The category of document to be printed.
///
/// Use this alongside `PrintMedium` to pick the correct paper preset and
/// SwiftUI view variant.
public enum PrintDocumentType: String, Sendable, CaseIterable, Codable {

    // MARK: - POS / transaction documents

    /// Standard point-of-sale receipt (thermal 80mm + A4 letter).
    case receipt             = "Receipt"
    /// Gift receipt — price-hidden variant.
    case giftReceipt         = "Gift Receipt"
    /// Refund receipt (thermal or letter).
    case refundReceipt       = "Refund Receipt"
    /// Z-report / end-of-day summary (thermal or letter).
    case zReport             = "Z-Report"

    // MARK: - Customer-facing documents

    /// Customer invoice with itemised line items, taxes, payment status.
    case invoice             = "Invoice"
    /// Estimate / quote for approval.
    case quote               = "Quote"

    // MARK: - Repair workflow documents

    /// Work order ticket — device + services authorised by customer.
    case workOrder           = "Work Order"
    /// Device intake form — pre-conditions checklist + customer signature.
    case intakeForm          = "Intake Form"
    /// Customer waiver — liability / data-loss / diagnostic-fee agreement + signature.
    case waiver              = "Waiver"
    /// Labor certificate — describes completed work for customer records.
    case laborCertificate    = "Labor Certificate"

    // MARK: - Accounting documents

    /// A/R statement — open balances for a customer.
    case arStatement         = "A/R Statement"
    /// Per-transaction or period tax summary.
    case taxSummary          = "Tax Summary"

    // MARK: - Helpers

    /// Human-readable display name (identical to rawValue here but exposed explicitly
    /// so callers don't depend on rawValue stability).
    public var displayName: String { rawValue }

    /// The preferred `PrintMedium` for this document type when no tenant override is set.
    public var defaultMedium: PrintMedium {
        switch self {
        case .receipt, .giftReceipt, .refundReceipt, .zReport:
            return .thermal80mm
        case .invoice, .quote, .workOrder, .intakeForm, .waiver,
             .laborCertificate, .arStatement, .taxSummary:
            return PrintMedium.tenantDefault
        }
    }

    /// True when this document type supports being paginated across multiple pages.
    public var supportsPagination: Bool {
        switch self {
        case .receipt, .giftReceipt, .refundReceipt, .zReport:
            return false   // thermal roll — continuous, not paginated
        default:
            return true
        }
    }
}

// MARK: - Job Payload (sum type)

public enum JobPayload: Sendable {
    case receipt(ReceiptPayload)
    case label(LabelPayload)
    case ticketTag(TicketTagPayload)
    case barcode(BarcodePayload)

    // MARK: - Convenience

    /// The preferred `PrintDocumentType` for this payload.
    /// Used by `PrintService` to pre-select the paper size in `PrintOptionsSheet`.
    public var documentType: PrintDocumentType {
        switch self {
        case .receipt:    return .receipt
        case .label:      return .invoice   // label stock for shelf tags
        case .ticketTag:  return .workOrder
        case .barcode:    return .receipt   // barcode slips are small; thermal default
        }
    }
}
