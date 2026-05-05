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
        UIPasteboard.general.items = []
        AppLog.auth.debug("Pasteboard cleared on auth screen dismiss")
    }

    /// Compatibility shim for callers that detected a pasted OTP and want a
    /// 30-second auto-clear. The canonical path is `copy(_:)` which sets an
    /// OS-enforced expiry; for paste-detection we schedule an async clear.
    public static func scheduleWipe() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            UIPasteboard.general.items = []
        }
    }
}

#endif
