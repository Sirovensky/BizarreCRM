import Foundation
import CoreSpotlight
import Core

// MARK: - SpotlightNSUserActivityIndexer

/// Produces `NSUserActivity` objects for BizarreCRM entities so that:
/// - CoreSpotlight re-ranks them as the user views records (`eligibleForSearch`).
/// - Siri Suggestions surfaces them at the right moment (`eligibleForPrediction`).
/// - Handoff lets the user continue the same record on another device.
///
/// **Usage — attach via `.userActivity` SwiftUI modifier:**
/// ```swift
/// TicketDetailView(ticket: ticket)
///     .userActivity(
///         SpotlightNSUserActivityIndexer.activityType(for: .ticket),
///         element: ticket
///     ) { ticket, activity in
///         SpotlightNSUserActivityIndexer.configure(activity, for: ticket)
///     }
/// ```
///
/// The indexer is a pure `enum` namespace — no stored state needed.
public enum SpotlightNSUserActivityIndexer {

    // MARK: - Activity type constants

    /// Activity type for ticket detail views.
    public static let ticketActivityType    = "com.bizarrecrm.activity.ticket"
    /// Activity type for customer detail views.
    public static let customerActivityType  = "com.bizarrecrm.activity.customer"
    /// Activity type for inventory item detail views.
    public static let inventoryActivityType = "com.bizarrecrm.activity.inventoryItem"

    // MARK: - Activity type lookup

    /// Return the registered activity-type string for a given `EntityKind`.
    public static func activityType(for kind: SpotlightEntityReference.EntityKind) -> String {
        switch kind {
        case .ticket:    return ticketActivityType
        case .customer:  return customerActivityType
        case .inventory: return inventoryActivityType
        }
    }

    // MARK: - Configuration helpers

    /// Configure an `NSUserActivity` to represent a `Ticket` detail view.
    ///
    /// Sets `title`, `webpageURL`, `userInfo`, and all Spotlight/Siri eligibility flags.
    /// The `contentAttributeSet` is populated so CoreSpotlight can re-rank the item
    /// based on actual usage rather than relying solely on the initial batch index.
    public static func configure(_ activity: NSUserActivity, for ticket: Ticket) {
        activity.title = "Ticket \(ticket.displayId) — \(ticket.customerName)"
        activity.userInfo = [
            "entityKind": SpotlightEntityReference.EntityKind.ticket.rawValue,
            "entityId": ticket.id,
            "uniqueIdentifier": ticket.spotlightUniqueIdentifier
        ]
        activity.requiredUserInfoKeys = Set(["entityKind", "entityId"])
        activity.isEligibleForHandoff   = true
        activity.isEligibleForSearch    = true
        activity.isEligibleForPrediction = true

        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = activity.title
        attrs.contentDescription = ticket.status.displayName
        if let device = ticket.deviceSummary { attrs.subject = device }
        attrs.keywords = [ticket.displayId, ticket.customerName, ticket.status.displayName, "ticket"]
        activity.contentAttributeSet = attrs

        if let url = URL(string: "bizarrecrm://tickets/\(ticket.id)") {
            activity.webpageURL = url
        }
    }

    /// Configure an `NSUserActivity` to represent a `Customer` detail view.
    public static func configure(_ activity: NSUserActivity, for customer: Customer) {
        activity.title = customer.displayName
        activity.userInfo = [
            "entityKind": SpotlightEntityReference.EntityKind.customer.rawValue,
            "entityId": customer.id,
            "uniqueIdentifier": customer.spotlightUniqueIdentifier
        ]
        activity.requiredUserInfoKeys = Set(["entityKind", "entityId"])
        activity.isEligibleForHandoff    = true
        activity.isEligibleForSearch     = true
        activity.isEligibleForPrediction = true

        let attrs = CSSearchableItemAttributeSet(contentType: .contact)
        attrs.title = customer.displayName
        var keywords: [String] = [customer.displayName, "customer"]
        if let phone = customer.phone {
            attrs.phoneNumbers = [phone]
            keywords.append(phone)
        }
        if let email = customer.email {
            attrs.emailAddresses = [email]
            keywords.append(email)
        }
        attrs.keywords = keywords
        activity.contentAttributeSet = attrs

        if let url = URL(string: "bizarrecrm://customers/\(customer.id)") {
            activity.webpageURL = url
        }
    }

    /// Configure an `NSUserActivity` to represent an `InventoryItem` detail view.
    public static func configure(_ activity: NSUserActivity, for item: InventoryItem) {
        activity.title = item.name
        activity.userInfo = [
            "entityKind": SpotlightEntityReference.EntityKind.inventory.rawValue,
            "entityId": item.id,
            "uniqueIdentifier": item.spotlightUniqueIdentifier
        ]
        activity.requiredUserInfoKeys = Set(["entityKind", "entityId"])
        activity.isEligibleForHandoff    = true
        activity.isEligibleForSearch     = true
        activity.isEligibleForPrediction = true

        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = item.name
        attrs.contentDescription = "SKU: \(item.sku)"
        var keywords = [item.name, item.sku, "inventory"]
        if let barcode = item.barcode { keywords.append(barcode) }
        attrs.keywords = keywords
        activity.contentAttributeSet = attrs

        if let url = URL(string: "bizarrecrm://inventory/\(item.id)") {
            activity.webpageURL = url
        }
    }
}
