import Foundation
import UserNotifications
import Core

// MARK: - §70 Rich push content builder
//
// Adds entity-specific context to notification body text for the three cases
// from the §70 matrix:
//   • SMS notification: embeds photo thumbnail if MMS (`thumbnail_url` field)
//   • Payment notification: shows amount + customer name in the body
//   • Ticket assignment: embeds device + status summary
//
// Called from `RichPushEnricher.enrich(_:userInfo:)` (NSE target) AND from
// `NotificationHandler` when composing local snooze re-fires.

/// Augments `UNMutableNotificationContent` with entity-specific rich body text
/// and attachment metadata.  Pure function — no side effects beyond mutating
/// the content object.
public enum RichPushContentBuilder {

    // MARK: - Public API

    /// Enrich notification content with entity-specific body text and metadata.
    ///
    /// Call after the basic title/body from `NotificationCopyProvider` is set.
    /// Replaces body if a richer version can be constructed from `userInfo`.
    ///
    /// - Parameters:
    ///   - content:  Mutable notification content (mutated in place).
    ///   - userInfo: Raw APNs payload dictionary.
    @available(iOS 15.0, *)
    public static func enrich(
        _ content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) {
        let eventType = userInfo["event_type"] as? String ?? ""

        switch eventType {

        // MARK: SMS inbound — embed message preview + MMS count
        case NotificationEvent.smsInbound.rawValue:
            if let preview = userInfo["message_preview"] as? String, !preview.isEmpty {
                let truncated = preview.count > 200
                    ? String(preview.prefix(200)) + "…"
                    : preview
                // Preserve the title set by NotificationCopyProvider; only enrich body.
                content.body = truncated
            }
            // MMS thumbnail is handled by RichPushEnricher's attachment download.
            // Flag `hasMMS` so the attachment path fires in the NSE.
            if let mmsURL = userInfo["mms_thumbnail_url"] as? String, !mmsURL.isEmpty {
                // Store the URL in userInfo subset for the NSE to pick up.
                var info = content.userInfo
                info["thumbnail_url"] = mmsURL
                content.userInfo = info
            }

        // MARK: Payment received — amount + customer name in body
        case NotificationEvent.invoicePaid.rawValue:
            let parts = richPaymentParts(userInfo: userInfo)
            if !parts.isEmpty {
                content.body = parts.joined(separator: " · ")
            }

        // MARK: Payment declined — amount + customer name in body
        case NotificationEvent.paymentDeclined.rawValue:
            let parts = richPaymentParts(userInfo: userInfo)
            if !parts.isEmpty {
                content.body = "Declined: " + parts.joined(separator: " · ")
            }

        // MARK: Ticket assigned — device + status in body
        case NotificationEvent.ticketAssigned.rawValue:
            var parts: [String] = []
            if let device = userInfo["device"] as? String { parts.append(device) }
            if let status = userInfo["status"] as? String { parts.append(status) }
            if let techNote = userInfo["tech_note"] as? String, !techNote.isEmpty {
                parts.append(String(techNote.prefix(80)))
            }
            if !parts.isEmpty {
                content.body = parts.joined(separator: " · ")
            }

        // MARK: Ticket status change — new status in body
        case NotificationEvent.ticketStatusChangeMine.rawValue,
             NotificationEvent.ticketStatusChangeAny.rawValue:
            if let status = userInfo["status"] as? String,
               let ticketId = userInfo["entity_id"] as? String ?? userInfo["entityId"] as? String {
                content.body = "Ticket #\(ticketId) → \(status)"
            }

        // MARK: Low stock / out-of-stock — SKU + count in body
        case NotificationEvent.lowStock.rawValue:
            if let sku = userInfo["sku"] as? String {
                let count = userInfo["quantity_on_hand"] as? Int ?? 0
                content.body = "SKU \(sku) — \(count) remaining"
            }

        case NotificationEvent.outOfStock.rawValue:
            if let sku = userInfo["sku"] as? String {
                content.body = "SKU \(sku) is out of stock"
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private static func richPaymentParts(userInfo: [AnyHashable: Any]) -> [String] {
        var parts: [String] = []
        if let amountStr = userInfo["amount"] as? String {
            parts.append("$\(amountStr)")
        } else if let amount = userInfo["amount"] as? Double {
            parts.append(String(format: "$%.2f", amount))
        }
        if let customer = userInfo["customer_name"] as? String, !customer.isEmpty {
            parts.append(customer)
        }
        if let invoiceId = userInfo["entity_id"] as? String ?? userInfo["entityId"] as? String {
            parts.append("Invoice #\(invoiceId)")
        }
        return parts
    }
}
