import Foundation
import UserNotifications

/// Handles `kind: "survey.autoSend"` push notifications delivered by the server
/// 24h after a ticket is closed.
///
/// The server triggers delivery timing — the client only needs to route the
/// notification tap to the correct survey sheet.
public enum SurveyAutoSender {

    /// Parse a `kind: "survey.autoSend"` notification payload and return
    /// a `SurveyTrigger` the host app can use to open the right sheet.
    ///
    /// Expected payload keys:
    /// - `surveyType`: "csat" | "nps"
    /// - `customerId`: String
    /// - `ticketId`: String (required for CSAT, optional for NPS)
    public static func parseTrigger(from userInfo: [AnyHashable: Any]) -> SurveyTrigger? {
        guard
            let kind = userInfo["kind"] as? String,
            kind == "survey.autoSend",
            let typeRaw = userInfo["surveyType"] as? String,
            let customerId = userInfo["customerId"] as? String
        else {
            return nil
        }

        let ticketId = userInfo["ticketId"] as? String ?? ""

        switch typeRaw {
        case "csat":
            return .csat(customerId: customerId, ticketId: ticketId)
        case "nps":
            return .nps(customerId: customerId)
        default:
            return nil
        }
    }
}

// MARK: - SurveyTrigger

/// Typed discriminator that the host app uses to present the right survey sheet.
public enum SurveyTrigger: Sendable {
    case csat(customerId: String, ticketId: String)
    case nps(customerId: String)
}
