import SwiftUI

// MARK: - HandoffEligibleView ViewModifier

/// Convenience modifier that advertises a screen for Handoff.
///
/// Retains an `NSUserActivity` for the lifetime of the modified view.
/// When the view disappears the activity is invalidated automatically.
///
/// **Usage:**
/// ```swift
/// TicketDetailView(ticket: ticket)
///     .handoffEligible(
///         type: HandoffActivityType.ticketView,
///         title: "Ticket #\(ticket.displayId)",
///         deepLink: URL(string: "bizarrecrm://acme/tickets/\(ticket.id)")!
///     )
/// ```
public struct HandoffEligibleModifier: ViewModifier {

    // MARK: Properties

    let activityType: String
    let title: String
    let deepLink: URL
    let entityId: String?

    @State private var activity: NSUserActivity?

    // MARK: Body

    public func body(content: Content) -> some View {
        content
            .onAppear {
                activity = HandoffPublisher.shared.publish(
                    activityType: activityType,
                    title: title,
                    deepLinkURL: deepLink,
                    entityId: entityId
                )
            }
            .onDisappear {
                activity?.invalidate()
                activity = nil
            }
    }
}

// MARK: - View extension

public extension View {
    /// Make this view eligible for Handoff / Continuity.
    ///
    /// - Parameters:
    ///   - type:      One of the `HandoffActivityType` constants.
    ///   - title:     Human-readable title for the Handoff dock icon.
    ///   - deepLink:  App deep link routed on the receiving device.
    ///   - entityId:  Optional opaque entity identifier stored in the activity.
    func handoffEligible(
        type: String,
        title: String,
        deepLink: URL,
        entityId: String? = nil
    ) -> some View {
        modifier(HandoffEligibleModifier(
            activityType: type,
            title: title,
            deepLink: deepLink,
            entityId: entityId
        ))
    }
}
