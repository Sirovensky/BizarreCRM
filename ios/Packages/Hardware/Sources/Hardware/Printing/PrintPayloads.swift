import Foundation

// MARK: - Receipt Payload

/// Full data needed to render a receipt on-device. Model is self-contained
/// (zero deferred network reads inside render) so printing works fully offline.
public struct ReceiptPayload: Sendable, Codable {
    public struct Line: Sendable, Codable {
        public let label: String
        public let value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

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
    public let cashierName: String
    public let footerMessage: String?
    public let qrContent: String?

    public init(
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
        cashierName: String,
        footerMessage: String? = nil,
        qrContent: String? = nil
    ) {
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

// MARK: - Job Payload (sum type)

public enum JobPayload: Sendable {
    case receipt(ReceiptPayload)
    case label(LabelPayload)
    case ticketTag(TicketTagPayload)
    case barcode(BarcodePayload)
}
