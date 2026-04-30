import Foundation
import Core
import Networking

// §8 — "Quote signed" push notification handler (staff side).
//
// When a customer signs an estimate via the public e-sign URL, the server
// sends an APNs push to the assigned staff user:
//   "Quote #42 signed by Acme Corp — convert to ticket?"
//
// The push payload carries:
//   {
//     aps: { alert: {...}, category: "bizarre.estimate.signed" },
//     entityId: "<estimateId>",
//     orderId:  "EST-042",
//     customerName: "Acme Corp"
//   }
//
// iOS actions in the notification:
//   • "View"    — deep-link to estimate detail.
//   • "Convert" — one-tap convert to ticket (foreground, no sheet needed).
//
// NOTE: The APNs category `bizarre.estimate.signed` and its action buttons
//       must be registered by Agent 9 (Notifications package). This file
//       provides the Estimates-side handler that the NotificationHandler
//       delegates to via the `DeepLinkHandling` protocol.
//       See Discovered section in ActionPlan.md for Agent 9 registration task.

// MARK: - Notification category + action IDs (read-only constants)

/// Category ID for the "estimate signed" push notification.
/// Registered server-side (category field in APNs payload).
public enum EstimateSignedNotificationCategory {
    /// Must match the `bizarre.estimate.signed` category registered by Agent 9.
    public static let categoryID = "bizarre.estimate.signed"

    /// Action: Open estimate detail in app.
    public static let actionView    = "bizarre.estimate.signed.view"
    /// Action: One-tap convert to ticket (foreground).
    public static let actionConvert = "bizarre.estimate.signed.convert"
}

// MARK: - Handler

/// Handles the `bizarre.estimate.signed` notification action taps.
///
/// The owning `NotificationHandler` should forward matching category events here.
/// Wire via dependency injection from the App target — do not use a singleton.
@MainActor
public final class EstimateSignedPushHandler: Sendable {
    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Handle action

    /// Called by `NotificationHandler` when the user taps a signed-estimate action.
    ///
    /// - Parameters:
    ///   - actionID: The tapped action identifier (see `EstimateSignedNotificationCategory`).
    ///   - estimateId: The estimate ID from the push payload's `entityId` field.
    ///   - onNavigateToEstimate: Called when the user taps "View". Navigate to estimate detail.
    ///   - onConvertedToTicket: Called on successful one-tap convert. Navigate to new ticket.
    public func handleAction(
        actionID: String,
        estimateId: Int64,
        onNavigateToEstimate: @escaping @MainActor (Int64) -> Void,
        onConvertedToTicket: @escaping @MainActor (Int64) -> Void
    ) async {
        switch actionID {
        case EstimateSignedNotificationCategory.actionView:
            onNavigateToEstimate(estimateId)

        case EstimateSignedNotificationCategory.actionConvert:
            await convertToTicket(
                estimateId: estimateId,
                onSuccess: onConvertedToTicket
            )

        default:
            // Default tap → navigate to estimate
            onNavigateToEstimate(estimateId)
        }
    }

    // MARK: - One-tap convert

    /// Performs the one-tap convert triggered from the notification action button.
    private func convertToTicket(
        estimateId: Int64,
        onSuccess: @MainActor (Int64) -> Void
    ) async {
        do {
            // §8 — Fetch the estimate first to get the approved version number,
            //      then convert locking to that version.
            let estimate = try await api.getEstimate(id: estimateId)
            let result = try await api.convertEstimateToTicketWithVersion(
                estimateId: estimateId,
                approvedVersionId: estimate.approvedVersionNumber.map { Int64($0) }
            )
            await onSuccess(result.ticketId)
        } catch {
            AppLog.ui.error(
                "Notification one-tap convert failed for estimate \(estimateId): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
