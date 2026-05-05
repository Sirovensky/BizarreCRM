import CoreSpotlight
import Core

// MARK: - CSSearchableIndexProtocol

/// Seam for dependency injection — lets tests swap in a stub index.
public protocol CSSearchableIndexProtocol: Sendable {
    func indexSearchableItems(_ items: [CSSearchableItem]) async throws
    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws
    func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws
}

extension CSSearchableIndex: CSSearchableIndexProtocol {
    public func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            deleteSearchableItems(withDomainIdentifiers: domainIdentifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - SpotlightIndexer

/// Manages CoreSpotlight indexing for all BizarreCRM entities.
///
/// As a Swift `actor` all mutations are serialised; callers can safely `await`
/// from any concurrency context.
///
/// **Usage:**
/// ```swift
/// let indexer = SpotlightIndexer()
/// try await indexer.indexTicket(ticket)
/// try await indexer.batchIndex(customers)
/// ```
public actor SpotlightIndexer {

    // MARK: Properties

    private let index: any CSSearchableIndexProtocol

    // MARK: Init

    /// Production init — uses the default system index.
    public init() {
        self.index = CSSearchableIndex.default()
    }

    /// Testable init — inject a stub index.
    public init(index: some CSSearchableIndexProtocol) {
        self.index = index
    }

    // MARK: - Convenience indexing methods

    /// Index a single ticket.
    public func indexTicket(_ ticket: Ticket) async throws {
        try await index.indexSearchableItems([ticket.toSearchableItem()])
    }

    /// Index a single customer.
    /// - Note: Marked `nothrow` intentionally; failures are logged rather than
    ///   surfaced to callers since indexing is best-effort.
    public func indexCustomer(_ customer: Customer) async {
        do {
            try await index.indexSearchableItems([customer.toSearchableItem()])
        } catch {
            AppLog.ui.error("SpotlightIndexer: failed to index customer \(customer.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Index a single inventory item.
    public func indexInventoryItem(_ item: InventoryItem) async {
        do {
            try await index.indexSearchableItems([item.toSearchableItem()])
        } catch {
            AppLog.ui.error("SpotlightIndexer: failed to index inventory item \(item.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Batch indexing

    /// Bulk-index any collection of `SpotlightIndexable` items.
    ///
    /// Splits into batches of 100 to stay within CoreSpotlight limits.
    public func batchIndex<T: SpotlightIndexable>(_ items: [T]) async throws {
        let batchSize = 100
        let searchableItems = items.map { $0.toSearchableItem() }
        var offset = 0
        while offset < searchableItems.count {
            let slice = Array(searchableItems[offset..<min(offset + batchSize, searchableItems.count)])
            try await index.indexSearchableItems(slice)
            offset += batchSize
        }
    }

    // MARK: - Removal

    /// Remove a single item by its unique identifier.
    public func removeItem(uniqueIdentifier: String) async throws {
        try await index.deleteSearchableItems(withIdentifiers: [uniqueIdentifier])
    }

    /// Remove all items in a domain (e.g. `"tickets"`, `"customers"`).
    public func removeDomain(_ domain: String) async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
    }
}
