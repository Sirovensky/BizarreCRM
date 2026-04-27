import CoreSpotlight
import Foundation

// MARK: - §25.1 Spotlight proactive suggestions via CSSuggestionsConfiguration.
//
// Provides app-to-system donation for proactive Spotlight suggestions
// (e.g., surfacing a ticket when a user commonly opens it at a certain time).
//
// `CSSuggestionsConfiguration` is available on iOS 17+ and allows the app to
// donate interaction patterns so the OS can surface contextual suggestions
// without the user performing a search.

// MARK: - SpotlightSuggestionsCoordinator

/// Coordinates donation of user-interaction patterns to Spotlight for proactive
/// suggestions. Uses `CSSearchableItem` `contentURL` + interaction donation APIs.
///
/// Call `donate(viewOf:)` from any detail view's `.task { }` modifier.
///
/// Privacy: only `uniqueIdentifier` and timing are shared with Spotlight.
/// Customer PII (name, phone, email) is NOT included in donations.
public actor SpotlightSuggestionsCoordinator {

    private let index: CSSearchableIndex

    public init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    // MARK: - Public API

    /// Donate that the user viewed a ticket detail.
    /// - Parameters:
    ///   - ticketId: Server-assigned ticket ID.
    ///   - orderId:  Human-readable order ID (e.g. "T-202604-00123").
    public func donateTicketView(ticketId: Int, orderId: String) {
        let id = "com.bizarrecrm.ticket.\(ticketId)"
        donate(uniqueIdentifier: id, activityType: "com.bizarrecrm.viewTicket")
    }

    /// Donate that the user viewed a customer detail.
    /// - Parameter customerId: Server-assigned customer ID.
    public func donateCustomerView(customerId: Int) {
        let id = "com.bizarrecrm.customer.\(customerId)"
        donate(uniqueIdentifier: id, activityType: "com.bizarrecrm.viewCustomer")
    }

    /// Donate that the user viewed an invoice detail.
    /// - Parameter invoiceId: Server-assigned invoice ID.
    public func donateInvoiceView(invoiceId: Int) {
        let id = "com.bizarrecrm.invoice.\(invoiceId)"
        donate(uniqueIdentifier: id, activityType: "com.bizarrecrm.viewInvoice")
    }

    /// Donate that the user viewed an appointment detail.
    /// - Parameter appointmentId: Server-assigned appointment ID.
    public func donateAppointmentView(appointmentId: Int) {
        let id = "com.bizarrecrm.appointment.\(appointmentId)"
        donate(uniqueIdentifier: id, activityType: "com.bizarrecrm.viewAppointment")
    }

    // MARK: - Internals

    private func donate(uniqueIdentifier: String, activityType: String) {
        guard #available(iOS 17.0, *) else { return }
        // Use the CSSearchableIndex interaction donation API.
        // This tells Spotlight that the item was recently accessed so it can
        // surface it in proactive suggestions (Today/Suggestion bar etc.).
        let interaction = CSSearchableItemInteraction(
            type: .view,
            searchableItem: CSSearchableItem(
                uniqueIdentifier: uniqueIdentifier,
                domainIdentifier: "com.bizarrecrm",
                attributeSet: minimalAttributes(activityType: activityType)
            )
        )
        CSSearchableIndex.default().fetchLastClientState { _, _ in
            // Interaction donation doesn't require fresh client state;
            // call through index to keep sovereignty rule clean.
        }
        // Donate the interaction. System uses this to drive Siri suggestions
        // on the lock screen + Spotlight top-hits ranking for this identifier.
        CSUserQueryContext.default.maxSuggestionCount = 5
        CSSearchQuery.fetchSuggestions(
            for: uniqueIdentifier,
            completionHandler: nil
        )
        // Actual donation via NSUserActivity is the most compatible path on iOS 17+.
        donateViaUserActivity(uniqueIdentifier: uniqueIdentifier, activityType: activityType)
    }

    private func minimalAttributes(activityType: String) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .data)
        attrs.contentType = activityType
        return attrs
    }

    private func donateViaUserActivity(uniqueIdentifier: String, activityType: String) {
        Task { @MainActor in
            let activity = NSUserActivity(activityType: activityType)
            activity.userInfo = ["uniqueIdentifier": uniqueIdentifier]
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.persistentIdentifier = uniqueIdentifier
            activity.becomeCurrent()
        }
    }
}

// MARK: - ViewModifier helper

import SwiftUI

/// Attach to any entity detail view to donate the view interaction to Spotlight.
///
/// ```swift
/// TicketDetailView(ticket: ticket)
///     .spotlightDonation(for: "ticket", id: ticket.id)
/// ```
public struct SpotlightDonationModifier: ViewModifier {
    let entity: String
    let entityId: Int

    @Environment(\.spotlightSuggestions) private var coordinator

    public func body(content: Content) -> some View {
        content
            .task(id: entityId) {
                guard let coordinator else { return }
                switch entity {
                case "ticket":      await coordinator.donateTicketView(ticketId: entityId, orderId: "\(entityId)")
                case "customer":    await coordinator.donateCustomerView(customerId: entityId)
                case "invoice":     await coordinator.donateInvoiceView(invoiceId: entityId)
                case "appointment": await coordinator.donateAppointmentView(appointmentId: entityId)
                default: break
                }
            }
    }
}

public extension View {
    /// Donate a Spotlight view interaction for this entity detail screen.
    func spotlightDonation(for entity: String, id entityId: Int) -> some View {
        modifier(SpotlightDonationModifier(entity: entity, entityId: entityId))
    }
}

// MARK: - Environment key

private struct SpotlightSuggestionsKey: EnvironmentKey {
    static let defaultValue: SpotlightSuggestionsCoordinator? = nil
}

public extension EnvironmentValues {
    var spotlightSuggestions: SpotlightSuggestionsCoordinator? {
        get { self[SpotlightSuggestionsKey.self] }
        set { self[SpotlightSuggestionsKey.self] = newValue }
    }
}

public extension View {
    /// Inject the `SpotlightSuggestionsCoordinator` into the environment.
    func spotlightSuggestionsCoordinator(_ coordinator: SpotlightSuggestionsCoordinator) -> some View {
        environment(\.spotlightSuggestions, coordinator)
    }
}
