import Foundation

/// §16.7 — Persist-the-render-model: snapshots the last `PosReceiptRenderer.Payload`
/// to UserDefaults at sale close so reprints are byte-for-byte identical even after
/// template or branding changes.
///
/// The payload is JSON-encoded (all fields are `Codable` via their primitive types).
/// A single slot is kept — the most-recently-closed sale. Older reprints come from
/// the server search flow (`ReprintSearchViewModel`).
///
/// Thread safety: `actor`-isolated. All reads and writes serialise through the
/// actor executor. Callers on `@MainActor` use `await` naturally.
public actor PosReceiptStore {

    public static let shared = PosReceiptStore()
    private init() {}

    private let defaults = UserDefaults.standard
    private let key = "com.bizarrecrm.pos.lastReceiptPayload"

    // MARK: - Write

    /// Persist `payload` as the most-recent receipt. Replaces any previous snapshot.
    /// Fire-and-forget from `PosView` at sale close (after tender confirmation).
    public func save(_ payload: PosReceiptRenderer.Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Read

    /// Return the last persisted payload, or `nil` when nothing has been saved yet.
    public func loadLast() -> PosReceiptRenderer.Payload? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PosReceiptRenderer.Payload.self, from: data)
    }

    /// Wipe the stored payload (e.g. on logout or tenant switch).
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Codable conformance for PosReceiptRenderer.Payload
//
// `Merchant` / `Line` / `Tender` get synthesised Codable via inline
// `: Codable` on their struct declarations in `PosReceiptRenderer.swift`
// (synthesis must live in the declaring file). The Payload itself uses
// a custom init/encode here so omitted defaults round-trip cleanly.

extension PosReceiptRenderer.Payload: Codable {
    enum CodingKeys: String, CodingKey {
        case merchant, date, customerName, orderNumber, lines,
             subtotalCents, discountCents, feesCents, taxCents, tipCents,
             totalCents, tenders, currencyCode, footer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = PosReceiptRenderer.Payload(
            merchant:       try c.decode(Merchant.self,  forKey: .merchant),
            date:           try c.decode(Date.self,      forKey: .date),
            customerName:   try c.decodeIfPresent(String.self, forKey: .customerName),
            orderNumber:    try c.decodeIfPresent(String.self, forKey: .orderNumber),
            lines:          try c.decode([Line].self,    forKey: .lines),
            subtotalCents:  try c.decode(Int.self,       forKey: .subtotalCents),
            discountCents:  try c.decode(Int.self,       forKey: .discountCents),
            feesCents:      try c.decode(Int.self,       forKey: .feesCents),
            taxCents:       try c.decode(Int.self,       forKey: .taxCents),
            tipCents:       try c.decode(Int.self,       forKey: .tipCents),
            totalCents:     try c.decode(Int.self,       forKey: .totalCents),
            tenders:        try c.decode([Tender].self,  forKey: .tenders),
            currencyCode:   try c.decode(String.self,    forKey: .currencyCode),
            footer:         try c.decodeIfPresent(String.self, forKey: .footer)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(merchant,      forKey: .merchant)
        try c.encode(date,          forKey: .date)
        try c.encodeIfPresent(customerName, forKey: .customerName)
        try c.encodeIfPresent(orderNumber,  forKey: .orderNumber)
        try c.encode(lines,         forKey: .lines)
        try c.encode(subtotalCents, forKey: .subtotalCents)
        try c.encode(discountCents, forKey: .discountCents)
        try c.encode(feesCents,     forKey: .feesCents)
        try c.encode(taxCents,      forKey: .taxCents)
        try c.encode(tipCents,      forKey: .tipCents)
        try c.encode(totalCents,    forKey: .totalCents)
        try c.encode(tenders,       forKey: .tenders)
        try c.encode(currencyCode,  forKey: .currencyCode)
        try c.encodeIfPresent(footer, forKey: .footer)
    }
}
