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

        switch typeRaw {
        case "csat":
            // BUGHUNT-2026-05-17: CSAT requires a valid ticketId so the
            // response row is attributed to the right service ticket
            // (per-tech CSAT averages depend on this — §37.3). The previous
            // code defaulted a missing ticketId to "" and still returned a
            // .csat trigger, which then POSTed `/surveys/csat` with an
            // empty ticketId — silently mis-attributing the rating and
            // skewing per-tech / manager-push thresholds. Refuse to build
            // the trigger when ticketId is missing or blank.
            guard
                let ticketId = userInfo["ticketId"] as? String,
                !ticketId.trimmingCharacters(in: .whitespaces).isEmpty
            else {
                return nil
            }
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
