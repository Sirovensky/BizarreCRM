import Foundation

/// §Agent-E — Post-sale receipt payload. Flows from the tender coordinator
/// into `PosReceiptViewModel` and from there to the share/print surfaces.
///
/// All money is in cents. Optional fields (`changeGivenCents`, `customerPhone`,
/// `customerEmail`, `loyaltyDelta`) are absent for walk-in sales and for
/// payment methods that don't produce change.
///
/// The payload is value-typed and `Sendable` so it can cross actor boundaries
/// without copying concerns. `Equatable` enables diffing in tests.
public struct PosReceiptPayload: Equatable, Sendable {

    // MARK: - Core fields

    /// Server-assigned invoice identifier. Used by the receipt-send endpoints.
    public let invoiceId: Int64

    /// Amount the customer handed / card-charged, in cents.
    public let amountPaidCents: Int

    /// Change returned for cash sales. Absent for card / gift card / store credit.
    public let changeGivenCents: Int?

    /// Human-readable tender method label shown in the hero, e.g. "Cash" or
    /// "Visa •4242". Produced by the tender coordinator from `AppliedTender`.
    public let methodLabel: String

    // MARK: - Customer contact

    /// E.164-normalised phone, if a customer is attached and has one.
    /// Drives the default share-channel pre-selection (SMS when present).
    public let customerPhone: String?

    /// Customer email, if available. Used to pre-fill the email share flow.
    public let customerEmail: String?

    // MARK: - Loyalty

    /// Points earned this sale (positive integer) or `nil` when no loyalty
    /// account is linked. `PosLoyaltyCelebrationView` is hidden when this is
    /// `nil` or `0`.
    public let loyaltyDelta: Int?

    /// Tier name before this sale (e.g. "Silver"). `nil` when no account.
    public let loyaltyTierBefore: String?

    /// Tier name after this sale. Matches `loyaltyTierBefore` if no tier-up
    /// occurred. `nil` when no account.
    public let loyaltyTierAfter: String?

    // MARK: - Loyalty progress

    /// Total loyalty points after this sale. Drives the left-side tier label
    /// "GOLD 285 pts" in `PosLoyaltyCelebrationView`.
    public let loyaltyPointsTotal: Int?

    /// Points threshold for the next tier. Drives the right-side label
    /// "PLATINUM 500 pts". Nil when the customer is already at the top tier.
    public let loyaltyNextTierPoints: Int?

    // MARK: - Cash detail

    /// Actual cash tendered (before change). Non-nil for cash transactions.
    /// Used by the hero subtitle "Cash · $300 received · $25.49 change".
    public let cashReceivedCents: Int?

    // MARK: - iPad Pencil signature

    /// Ticket identifier to which a Pencil-captured signature was archived.
    /// Non-nil on iPad when the cashier used `PKCanvasView` to collect a
    /// signature before or after tender. The receipt screen shows a teal
    /// confirmation banner (iPad only). Nil on iPhone or when unsigned.
    public let signedTicketId: Int64?

    // MARK: - §16.24 — Repair ticket linkage

    /// Linked repair ticket identifier (from `Cart.linkedTicketId` at sale close).
    /// When non-nil, the §16.24 receipt screen shows "Parts reserved to Ticket #NNNN"
    /// in teal and an "Open ticket #NNNN" secondary CTA button.
    public let linkedRepairTicketId: Int64?

    // MARK: - Init

    public init(
        invoiceId: Int64,
        amountPaidCents: Int,
        changeGivenCents: Int? = nil,
        cashReceivedCents: Int? = nil,
        methodLabel: String,
        customerPhone: String? = nil,
        customerEmail: String? = nil,
        loyaltyDelta: Int? = nil,
        loyaltyTierBefore: String? = nil,
        loyaltyTierAfter: String? = nil,
        loyaltyPointsTotal: Int? = nil,
        loyaltyNextTierPoints: Int? = nil,
        signedTicketId: Int64? = nil,
        linkedRepairTicketId: Int64? = nil
    ) {
        self.invoiceId = invoiceId
        self.amountPaidCents = amountPaidCents
        self.changeGivenCents = changeGivenCents
        self.cashReceivedCents = cashReceivedCents
        self.methodLabel = methodLabel
        self.customerPhone = customerPhone
        self.customerEmail = customerEmail
        self.loyaltyDelta = loyaltyDelta
        self.loyaltyTierBefore = loyaltyTierBefore
        self.loyaltyTierAfter = loyaltyTierAfter
        self.loyaltyPointsTotal = loyaltyPointsTotal
        self.loyaltyNextTierPoints = loyaltyNextTierPoints
        self.signedTicketId = signedTicketId
        self.linkedRepairTicketId = linkedRepairTicketId
    }
}
