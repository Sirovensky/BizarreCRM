import CoreSpotlight
import Core

// MARK: - SpotlightIndexable

/// Adopted by Search-package-level wrappers that know how to produce a
/// `CSSearchableItem` for a given domain model.
///
/// Domain packages themselves do **not** conform — Search owns the shape.
public protocol SpotlightIndexable: Sendable {
    /// Spotlight domain bucket (e.g. `"tickets"`, `"customers"`).
    var spotlightDomain: String { get }

    /// Globally-unique identifier for the item within the index.
    /// Format: `"bizarrecrm.<domain>.<id>"`.
    var spotlightUniqueIdentifier: String { get }

    /// Build the `CSSearchableItem` ready for indexing.
    func toSearchableItem() -> CSSearchableItem
}

// MARK: - Ticket conformance

extension Ticket: SpotlightIndexable {
    public var spotlightDomain: String { "tickets" }

    public var spotlightUniqueIdentifier: String {
        "bizarrecrm.ticket.\(id)"
    }

    public func toSearchableItem() -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = "Ticket \(displayId) — \(customerName)"
        attrs.contentDescription = "\(status.displayName)\(deviceSummary.map { " · \($0)" } ?? "")"
        attrs.keywords = [displayId, customerName, status.displayName, "ticket"]
        attrs.domainIdentifier = spotlightDomain
        let item = CSSearchableItem(
            uniqueIdentifier: spotlightUniqueIdentifier,
            domainIdentifier: spotlightDomain,
            attributeSet: attrs
        )
        item.expirationDate = .distantFuture
        return item
    }
}

// MARK: - Customer conformance

extension Customer: SpotlightIndexable {
    public var spotlightDomain: String { "customers" }

    public var spotlightUniqueIdentifier: String {
        "bizarrecrm.customer.\(id)"
    }

    public func toSearchableItem() -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .contact)
        attrs.title = displayName
        var desc = [String]()
        if let phone { desc.append(phone) }
        if let email { desc.append(email) }
        attrs.contentDescription = desc.joined(separator: " · ")
        attrs.keywords = ([displayName] + desc + ["customer"]).filter { !$0.isEmpty }
        attrs.domainIdentifier = spotlightDomain
        let item = CSSearchableItem(
            uniqueIdentifier: spotlightUniqueIdentifier,
            domainIdentifier: spotlightDomain,
            attributeSet: attrs
        )
        item.expirationDate = .distantFuture
        return item
    }
}

// MARK: - InventoryItem conformance

extension InventoryItem: SpotlightIndexable {
    public var spotlightDomain: String { "inventory" }

    public var spotlightUniqueIdentifier: String {
        "bizarrecrm.inventory.\(id)"
    }

    public func toSearchableItem() -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = name
        attrs.contentDescription = "SKU: \(sku)"
        attrs.keywords = [name, sku, "inventory"]
        if let barcode { attrs.keywords?.append(barcode) }
        attrs.domainIdentifier = spotlightDomain
        let item = CSSearchableItem(
            uniqueIdentifier: spotlightUniqueIdentifier,
            domainIdentifier: spotlightDomain,
            attributeSet: attrs
        )
        item.expirationDate = .distantFuture
        return item
    }
}
