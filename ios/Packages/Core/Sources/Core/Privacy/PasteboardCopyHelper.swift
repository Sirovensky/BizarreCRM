#if canImport(UIKit)
import Foundation
import UIKit

// §28.9 Pasteboard hygiene — Copy helpers
//
// Two contracts:
//
//   1. `copyNonSensitive(_:)` — ticket IDs, invoice numbers, SKUs, names,
//      emails, phones. Lives forever on the pasteboard (no expiration);
//      iOS Universal Clipboard syncs to the user's other devices. No audit
//      trail because the data is intentionally user-shareable.
//
//   2. `copySensitive(_:expiresIn:screen:)` — 2FA backup codes, server-issued
//      one-time passwords, similar short-lived secrets. Uses
//      `UIPasteboard.setItems(_:options:)` with `.expirationDate` so iOS
//      auto-clears the entry after `expiresIn` seconds (default 60s per
//      §28.9). Writes a `PasteboardAudit.logWrite(...)` entry so tenant
//      admins see when sensitive copies happened.
//
// Both helpers de-duplicate identical writes inside a 3-second window so
// rapid double-taps do not generate a flood of audit entries / haptics.

// MARK: - PasteboardCopyHelper

public enum PasteboardCopyHelper {

    // MARK: - Internal de-dupe state

    private static let dedupeWindow: TimeInterval = 3
    private static var lastValueHash: Int = 0
    private static var lastWriteAt: Date = .distantPast
    private static let lock = NSLock()

    // MARK: - Public API

    /// Copy a non-sensitive string (ticket IDs, customer names, emails).
    /// Idempotent inside a 3-second window — calling twice with the same value
    /// is a no-op (returns `false` the second time so callers can suppress the
    /// haptic / toast spam).
    ///
    /// - Parameter value: The string to copy.
    /// - Returns: `true` if the pasteboard was actually written, `false` if
    ///            this was a duplicate inside the de-dupe window.
    @discardableResult
    public static func copyNonSensitive(_ value: String) -> Bool {
        guard shouldWrite(value) else { return false }
        UIPasteboard.general.string = value
        return true
    }

    /// Copy a sensitive string (2FA backup code, server-issued OTP) that should
    /// auto-clear from the pasteboard after `expiresIn` seconds.
    ///
    /// Behind the scenes uses `UIPasteboard.setItems(_:options:)` with the
    /// `.expirationDate` option (iOS 10+). Also fires
    /// `PasteboardAudit.logWrite(...)` so the action is reviewable.
    ///
    /// - Parameters:
    ///   - value:     The sensitive string.
    ///   - expiresIn: Lifetime in seconds; defaults to 60 per §28.9.
    ///   - screen:    Stable screen identifier for the audit entry
    ///                (e.g. `"twoFactor.backupCodes"`).
    /// - Returns: `true` if the pasteboard was written, `false` on de-dupe.
    @discardableResult
    public static func copySensitive(
        _ value: String,
        expiresIn: TimeInterval = 60,
        screen: String
    ) -> Bool {
        guard shouldWrite(value) else { return false }

        let item: [String: Any] = [UIPasteboard.typeAutomatic: value]
        let expirationDate = Date().addingTimeInterval(expiresIn)

        UIPasteboard.general.setItems(
            [item],
            options: [
                .expirationDate: expirationDate,
                .localOnly:      true,   // Don't push secret to Universal Clipboard
            ]
        )

        PasteboardAudit.logWrite(screen: screen, expiresIn: expiresIn)
        return true
    }

    /// Force-clear the system pasteboard. Useful after the user pastes a
    /// sensitive value into our app and we want to remove the residue.
    public static func clear() {
        UIPasteboard.general.items = []
        lock.lock()
        lastValueHash = 0
        lastWriteAt = .distantPast
        lock.unlock()
    }

    // MARK: - Private

    /// Returns `true` if `value` is different from the last copy or the
    /// de-dupe window has expired. Updates the de-dupe state on `true`.
    private static func shouldWrite(_ value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let hash = value.hashValue
        let now  = Date()
        let elapsed = now.timeIntervalSince(lastWriteAt)

        if hash == lastValueHash, elapsed < dedupeWindow {
            return false
        }
        lastValueHash = hash
        lastWriteAt = now
        return true
    }
}
#endif
