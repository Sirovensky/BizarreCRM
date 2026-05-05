import Foundation

// §21.9 FocusFilterIntent stub — disabled while AppIntents macros are
// not compiling under strict concurrency. Re-enable when the suppression
// behavior is wired and the target supports the focus entitlement.

public enum FocusNotificationMode: String, Codable, Sendable {
    case all
    case assigned
    case mentions
    case off
}
