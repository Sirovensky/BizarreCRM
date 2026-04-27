import Foundation

// MARK: - GiftReceiptChannel

/// The delivery channel for a gift receipt.
///
/// §16 — "Channels: print + email + SMS + AirDrop"
public enum GiftReceiptChannel: String, CaseIterable, Sendable, Hashable {
    case print   = "print"
    case email   = "email"
    case sms     = "sms"
    case airDrop = "airdrop"

    public var displayName: String {
        switch self {
        case .print:   return "Print"
        case .email:   return "Email"
        case .sms:     return "SMS"
        case .airDrop: return "AirDrop"
        }
    }

    public var iconName: String {
        switch self {
        case .print:   return "printer.fill"
        case .email:   return "envelope.fill"
        case .sms:     return "message.fill"
        case .airDrop: return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - GiftReceiptReturnCredit

/// Where store credit for gift returns is applied.
///
/// §16 — "Return handling: gift return credits store credit (§40) by default
///         unless paid-for matches card on file"
public enum GiftReceiptReturnCredit: String, CaseIterable, Sendable, Hashable {
    /// Credits the customer's store-credit balance (default).
    case storeCredit = "store_credit"
    /// Refunds to the original card on file (requires matching original tender).
    case originalCard = "original_card"

    public var displayName: String {
        switch self {
        case .storeCredit:  return "Store credit (default)"
        case .originalCard: return "Original card on file"
        }
    }
}

// MARK: - GiftReceiptOptions

/// The complete set of options configured by the cashier in the gift-receipt
/// checkout sheet before printing / sending.
///
/// All fields default to the most conservative / PCI-safe option:
/// - No partial selection → all lines included.
/// - Return credit → store credit.
/// - Return-by date → 30 days from sale.
public struct GiftReceiptOptions: Sendable, Equatable {
    /// Whether to generate a gift receipt at all (the checkout-toggle switch).
    public var enabled: Bool
    /// Set of line IDs to include in the gift receipt.
    /// An empty set means **all lines** (full receipt mode).
    public var includedLineIds: Set<Int64>
    /// Whether partial-receipt mode is active (cashier picked specific lines).
    public var isPartial: Bool { !includedLineIds.isEmpty }
    /// Delivery channel chosen by the cashier.
    public var channel: GiftReceiptChannel
    /// Number of days from the sale date before the return window closes.
    public var returnByDays: Int
    /// Return credit destination.
    public var returnCredit: GiftReceiptReturnCredit

    // MARK: - Derived

    /// Human-readable return-by date from the reference sale date.
    public func returnByDate(from saleDate: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: returnByDays, to: saleDate) ?? saleDate
    }

    /// Formatted return-by date string (e.g. "May 26, 2026").
    public func returnByDateString(from saleDate: Date = .now) -> String {
        Self.displayFormatter.string(from: returnByDate(from: saleDate))
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: - Defaults

    public static let `default` = GiftReceiptOptions(
        enabled: false,
        includedLineIds: [],
        channel: .print,
        returnByDays: 30,
        returnCredit: .storeCredit
    )

    public init(
        enabled: Bool = false,
        includedLineIds: Set<Int64> = [],
        channel: GiftReceiptChannel = .print,
        returnByDays: Int = 30,
        returnCredit: GiftReceiptReturnCredit = .storeCredit
    ) {
        self.enabled        = enabled
        self.includedLineIds = includedLineIds
        self.channel        = channel
        self.returnByDays   = returnByDays
        self.returnCredit   = returnCredit
    }
}
