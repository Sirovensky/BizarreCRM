#if canImport(UIKit)
import UIKit
import Foundation
import Core

// MARK: - §2.13 Pasteboard OTP expiry (30s)

/// Clears OTP / backup-code values copied to the pasteboard after 30 seconds.
///
/// **Usage:**
/// ```swift
/// OTPPasteboardCleaner.copy("123456")  // Sets value + 30s expiry
/// ```
///
/// This satisfies the §2.13 requirement: "Pasteboard clears OTP after 30s".
/// Using `UIPasteboard.general.expirationDate` so the OS enforces the timeout
/// even if the app is suspended.
public enum OTPPasteboardCleaner {

    /// Copy `value` to the system pasteboard with a 30-second expiry.
    ///
    /// - Parameter value: The sensitive string (OTP code, backup code) to copy.
    public static func copy(_ value: String) {
        let expiry = Date(timeIntervalSinceNow: 30)
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: value]],
            options: [.expirationDate: expiry]
        )
        AppLog.auth.debug("Copied sensitive value to pasteboard; expires in 30 s")
    }

    /// Immediately clear the pasteboard if it currently holds a known OTP value.
    /// Called when the 2FA screen disappears or the user completes auth.
    public static func clearIfSensitive() {
        // We can't read the pasteboard content to compare (that would require
        // user consent on iOS 14+), so we always clear on explicit dismiss —
        // this is conservative and expected by the spec.
        UIPasteboard.general.items = []
        AppLog.auth.debug("Pasteboard cleared on auth screen dismiss")
    }
}

#endif
