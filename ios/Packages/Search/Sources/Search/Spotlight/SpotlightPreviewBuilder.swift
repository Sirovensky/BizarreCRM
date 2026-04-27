import CoreSpotlight
import Core

// MARK: - §25.1 Spotlight preview — rich preview card with avatar/thumbnail + status
//
// Extends the existing SpotlightIndexable conformances to set `contentURL`
// (enables the Spotlight preview card) and `thumbnailData` (avatar or status icon).
//
// The `contentURL` must point to a deep-link URL the app can handle via
// `application(_:continue:restorationHandler:)`.  The URL scheme handler
// (`CustomSchemeHandler` / `UniversalLinkHandler`) already processes these.
//
// Privacy gate (§18.3): when the device is in Apple Intelligence privacy mode
// (Data & Privacy → Apple Intelligence → "Don't allow Apple to use your data"),
// `CSSearchableItemAttributeSet` rejects phone / email being indexed.
// We guard on `includeContactDetails` (stored in UserDefaults by
// `SpotlightSettingsView`) before setting `phoneNumbers` / `emailAddresses`.

/// Builds rich `CSSearchableItemAttributeSet` instances for Spotlight preview cards.
public enum SpotlightPreviewBuilder {

    // MARK: - Public API

    /// Enrich an attribute set with preview-card data for a ticket.
    /// Sets `contentURL` (deep-link), `contentDescription` with status,
    /// and optionally a thumbnail if photo data is available.
    public static func enrich(
        attrs: CSSearchableItemAttributeSet,
        ticket: Ticket,
        tenantSlug: String,
        thumbnailData: Data? = nil
    ) {
        // Deep-link — enables the "Preview" button in Spotlight.
        attrs.contentURL = URL(string: "bizarrecrm://\(tenantSlug)/tickets/\(ticket.id)")

        // Richer description for preview card.
        var desc = ticket.status.displayName
        if let device = ticket.deviceSummary { desc += " · \(device)" }
        if let notes = ticket.technicianNotes, !notes.isEmpty {
            let truncated = String(notes.prefix(120))
            desc += "\n\(truncated)"
        }
        attrs.contentDescription = desc

        // Thumbnail — ticket photo or status-colored icon data.
        if let data = thumbnailData {
            attrs.thumbnailData = data
        }

        // Keywords including ticket ID for exact-match search.
        var kw = attrs.keywords ?? []
        kw.append(contentsOf: [ticket.displayId, "ticket", ticket.status.displayName])
        attrs.keywords = kw.uniqued()
    }

    /// Enrich an attribute set with preview-card data for a customer.
    public static func enrich(
        attrs: CSSearchableItemAttributeSet,
        customer: Customer,
        tenantSlug: String,
        avatarData: Data? = nil,
        includeContactDetails: Bool = true
    ) {
        attrs.contentURL = URL(string: "bizarrecrm://\(tenantSlug)/customers/\(customer.id)")

        var kw = attrs.keywords ?? []

        // Contact fields — gated on privacy setting.
        if includeContactDetails {
            if let phone = customer.phone {
                attrs.phoneNumbers = [phone]
                kw.append(phone)
            }
            if let email = customer.email {
                attrs.emailAddresses = [email]
                kw.append(email)
            }
        }

        kw.append(contentsOf: [customer.displayName, "customer"])
        attrs.keywords = kw.uniqued()

        // Avatar thumbnail.
        if let data = avatarData {
            attrs.thumbnailData = data
        }
    }

    /// Enrich an attribute set with preview-card data for an invoice.
    public static func enrich(
        attrs: CSSearchableItemAttributeSet,
        invoice: Invoice,
        tenantSlug: String
    ) {
        attrs.contentURL = URL(string: "bizarrecrm://\(tenantSlug)/invoices/\(invoice.id)")

        let amountStr = String(format: "$%.2f", invoice.total)
        attrs.contentDescription = "\(invoice.status.displayName) · \(amountStr)"

        var kw = attrs.keywords ?? []
        kw.append(contentsOf: [invoice.displayId, "invoice", invoice.status.displayName, amountStr])
        attrs.keywords = kw.uniqued()
    }

    /// Enrich an attribute set for an appointment.
    public static func enrich(
        attrs: CSSearchableItemAttributeSet,
        appointment: Appointment,
        tenantSlug: String
    ) {
        attrs.contentURL = URL(string: "bizarrecrm://\(tenantSlug)/appointments/\(appointment.id)")

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        attrs.contentDescription = df.string(from: appointment.startTime)
            + (appointment.notes.map { " · \($0)" } ?? "")

        var kw = attrs.keywords ?? []
        kw.append(contentsOf: [appointment.customerName, "appointment"])
        attrs.keywords = kw.uniqued()
    }
}

// MARK: - Privacy gate helper

/// Reads the user-facing "Disable Spotlight" opt-out and contact-detail flag
/// from UserDefaults.  Set by `SpotlightSettingsView`.
public enum SpotlightPrivacyGate {

    private static let defaults = UserDefaults.standard
    private static let disableKey        = "spotlight.disabled"
    private static let contactDetailKey  = "spotlight.includeContactDetails"

    /// Returns `true` when Spotlight indexing is enabled for this device.
    public static var isEnabled: Bool {
        !defaults.bool(forKey: disableKey)
    }

    /// Returns `true` when phone/email fields may be indexed.
    public static var includeContactDetails: Bool {
        // Default: true; user can opt out via Settings → Privacy → Spotlight.
        !defaults.bool(forKey: "spotlight.excludeContactDetails")
    }
}

// MARK: - Array uniqued helper (local, no Core dep)

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
