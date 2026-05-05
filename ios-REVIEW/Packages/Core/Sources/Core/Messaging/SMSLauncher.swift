#if canImport(UIKit)
import UIKit
#endif
import Foundation

// MARK: - MessagingMode preference
//
// On iOS / iPadOS we cannot become the default SMS app (Apple reserves that
// for Messages.app). The product policy is: in-app messaging is the default
// for every "SMS this customer" entry point (Customers, Tickets, Leads,
// Appointments, Marketing alerts, etc.). The user can opt into using the
// device Messages app instead — that flag also disables our Communications
// module entirely so we don't double-store outbound history.
//
// On Android (separate app) we *can* become the default SMS / call app, in
// which case the same flag flips the implementation. iOS only honours the
// `.device` branch by handing off to `sms:<phone>` URL.

public enum MessagingMode: String, CaseIterable, Sendable {
    /// Default — open the in-app Communications thread for this phone.
    case inApp = "in_app"
    /// Hand off to the system Messages app (`sms:<phone>` URL). Also hides
    /// the Communications rail destination because we no longer own the
    /// conversation history for that user.
    case device = "device"
}

/// Persistence + change-notification for the messaging mode toggle.
public enum MessagingPreference {
    private static let defaultsKey = "messaging.mode"

    public static var mode: MessagingMode {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? MessagingMode.inApp.rawValue
            return MessagingMode(rawValue: raw) ?? .inApp
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .messagingModeChanged, object: newValue)
        }
    }

    /// Convenience — `true` when in-app messaging is enabled (default).
    public static var useInAppMessaging: Bool { mode == .inApp }
}

public extension Notification.Name {
    /// Posted whenever `MessagingPreference.mode` changes. Observers should
    /// re-evaluate rail visibility / SMS button styling.
    static let messagingModeChanged = Notification.Name("MessagingModeChanged")
    /// Posted by `SMSLauncher` when the user taps a "SMS this customer"
    /// affordance and `MessagingPreference.mode == .inApp`. The host
    /// (iPadShell / iPhone tab coordinator) switches to the SMS tab and
    /// pushes the thread for the given phone number. The object is the
    /// already-cleaned digits-only phone string.
    static let openInAppSMSThread = Notification.Name("OpenInAppSMSThread")
}

// MARK: - SMSLauncher
//
// Single entry-point all "SMS this customer" callers should use instead of
// hand-rolling `URL(string: "sms:\(...)") + UIApplication.shared.open(url)`.
// Honours `MessagingPreference.mode`:
//   .inApp  → posts `Notification.Name.openInAppSMSThread` with the cleaned
//             phone; the app shell switches to the SMS tab and pushes the
//             matching thread.
//   .device → opens `sms:<digits>` so iOS hands off to Messages.app.
//
// Use:
//   SMSLauncher.open(phone: customer.phone)

@MainActor
public enum SMSLauncher {
    /// Opens the SMS surface for the given raw phone number. Strips
    /// non-digit characters (keeping a leading `+`). No-ops on empty input.
    public static func open(phone: String?) {
        guard let raw = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return }

        switch MessagingPreference.mode {
        case .inApp:
            NotificationCenter.default.post(name: .openInAppSMSThread, object: digits)
        case .device:
            #if canImport(UIKit)
            if let url = URL(string: "sms:\(digits)") {
                UIApplication.shared.open(url)
            }
            #endif
        }
    }
}
