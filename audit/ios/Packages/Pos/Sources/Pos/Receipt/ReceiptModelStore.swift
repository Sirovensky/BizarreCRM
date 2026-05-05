import Foundation

/// §16.7 — Persists a snapshot of `PosReceiptPayload` at sale close so that
/// reprints produce byte-identical output even after branding / template
/// changes. Uses `UserDefaults` (group container) as an MVP backing store;
/// GRDB migration is deferred to Phase 5.
///
/// The store keeps the most recent 50 receipts by invoice ID. Older entries
/// are pruned on write to stay under the `UserDefaults` 4MB soft limit.
///
/// Actor isolation guarantees no concurrent mutations.
public actor ReceiptModelStore {

    // MARK: - Singleton

    public static let shared = ReceiptModelStore()
    private init() {}

    // MARK: - Types

    /// Persisted receipt snapshot — a `Codable` parallel to `PosReceiptPayload`
    /// with the receipt text included so the reprint path is self-contained.
    public struct StoredReceiptModel: Codable, Sendable, Identifiable {
        public let id: Int64            // == invoiceId
        public let savedAt: Date
        public let invoiceId: Int64
        public let receiptNumber: String
        public let amountPaidCents: Int
        public let changeGivenCents: Int?
        public let methodLabel: String
        public let customerName: String?
        public let customerPhone: String?
        public let customerEmail: String?
        public let receiptText: String?  // rendered text snapshot for reprint

        public init(
            invoiceId: Int64,
            receiptNumber: String,
            amountPaidCents: Int,
            changeGivenCents: Int? = nil,
            methodLabel: String,
            customerName: String? = nil,
            customerPhone: String? = nil,
            customerEmail: String? = nil,
            receiptText: String? = nil
        ) {
            self.id = invoiceId
            self.savedAt = Date()
            self.invoiceId = invoiceId
            self.receiptNumber = receiptNumber
            self.amountPaidCents = amountPaidCents
            self.changeGivenCents = changeGivenCents
            self.methodLabel = methodLabel
            self.customerName = customerName
            self.customerPhone = customerPhone
            self.customerEmail = customerEmail
            self.receiptText = receiptText
        }
    }

    // MARK: - Storage key

    private static let storageKey = "com.bizarrecrm.pos.receiptModels"
    private static let maxStored  = 50

    // MARK: - Public API

    /// Persist a receipt model. Evicts the oldest entries if the store
    /// exceeds `maxStored`.
    public func save(_ model: StoredReceiptModel) {
        var all = loadAll()
        all.removeAll { $0.invoiceId == model.invoiceId }
        all.append(model)
        if all.count > Self.maxStored {
            all = Array(all.suffix(Self.maxStored))
        }
        persist(all)
    }

    /// Retrieve a specific stored receipt by invoice ID, or `nil` if not found.
    public func load(invoiceId: Int64) -> StoredReceiptModel? {
        loadAll().first { $0.invoiceId == invoiceId }
    }

    /// All stored receipts, newest first.
    public func allNewestFirst() -> [StoredReceiptModel] {
        loadAll().reversed()
    }

    // MARK: - Internals

    private func loadAll() -> [StoredReceiptModel] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([StoredReceiptModel].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist(_ models: [StoredReceiptModel]) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
