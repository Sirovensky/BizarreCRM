#if canImport(UIKit)
import SwiftUI
import UIKit
import Core

// MARK: - AuthPrivacyModifiers
//
// §2.13 — Privacy hardening for auth screens:
//
//  1. `privacySensitive()` + `.redacted(reason: .privacy)` on password fields
//     when the app transitions to background.
//
//  2. Blur overlay on screenshots during 2FA + password entry
//     (listen to UIScreen.capturedDidChange).
//
//  3. Pasteboard auto-clear: after pasting a 6-digit OTP, schedule a 30s
//     wipe of UIPasteboard.general (per §2.13 spec).
//
//  4. Challenge-token staleness: 10 min after the 2FA challenge was issued,
//     silently return the user to the credentials step with an error.

// MARK: - Screen-capture blur

/// Blurs the view it's applied to whenever iOS screen recording / mirroring
/// is active. Use on 2FA and password panels.
private struct ScreenCaptureBlurModifier: ViewModifier {
    @State private var isCaptured: Bool = UIScreen.main.isCaptured

    func body(content: Content) -> some View {
        content
            .blur(radius: isCaptured ? 20 : 0)
            .animation(BrandMotion.snappy, value: isCaptured)
            .onReceive(
                NotificationCenter.default
                    .publisher(for: UIScreen.capturedDidChangeNotification)
            ) { _ in
                isCaptured = UIScreen.main.isCaptured
            }
            .accessibilityLabel(isCaptured ? "Content hidden — screen recording active" : "")
    }
}

public extension View {
    /// Blurs content while iOS screen recording / AirPlay mirroring is active.
    func authScreenCaptureBlur() -> some View {
        modifier(ScreenCaptureBlurModifier())
    }
}

// MARK: - Background redaction

/// Applies `.privacySensitive()` + `.redacted(reason: .privacy)` when the
/// app enters background phase. Use on password / PIN fields.
private struct BackgroundRedactionModifier: ViewModifier {
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .privacySensitive()
            .redacted(reason: phase == .background ? .privacy : [])
    }
}

public extension View {
    /// Redacts sensitive content when the app moves to the background.
    func authPrivacyRedacted() -> some View {
        modifier(BackgroundRedactionModifier())
    }
}

// MARK: - OTP pasteboard auto-clear

/// After a 6-digit OTP is pasted, schedules a 30-second wipe of the
/// system pasteboard so the code doesn't linger for other apps to read.
///
/// Usage:
/// ```swift
/// TextField("000 000", text: $code)
///     .onChange(of: code) { _, new in
///         if new.filter(\.isNumber).count == 6 {
///             OTPPasteboardCleaner.scheduleWipe()
///         }
///     }
/// ```
public enum OTPPasteboardCleaner {
    private static var wipeTask: Task<Void, Never>?

    /// Schedules a one-shot wipe of `UIPasteboard.general` after 30 seconds.
    /// If called again before 30s, the previous timer resets.
    public static func scheduleWipe() {
        wipeTask?.cancel()
        wipeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            // Clear only if the current content looks like a bare OTP string
            // (digits only, 6 chars) to avoid wiping unrelated clipboard content.
            if let str = UIPasteboard.general.string,
               str.filter(\.isNumber) == str,
               str.count == 6 {
                UIPasteboard.general.string = ""
                AppLog.auth.debug("OTP cleared from pasteboard after 30s")
            }
        }
    }

    /// Cancels any pending wipe (call on view disappear / step change).
    public static func cancelWipe() {
        wipeTask?.cancel()
        wipeTask = nil
    }
}

// MARK: - Challenge-token expiry guard

/// §2.13 — The server issues a challenge token that expires after 10 minutes.
/// This view modifier silently fires `onExpired` when 10 minutes have elapsed
/// since `issuedAt`, so callers can redirect back to the credentials step.
private struct ChallengeTokenExpiryModifier: ViewModifier {
    let issuedAt: Date
    let onExpired: () -> Void

    func body(content: Content) -> some View {
        content.task {
            let deadline = issuedAt.addingTimeInterval(10 * 60)
            let delay = deadline.timeIntervalSinceNow
            guard delay > 0 else { onExpired(); return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onExpired()
        }
    }
}

public extension View {
    /// Calls `onExpired` after 10 minutes from `issuedAt`.
    /// Use on the 2FA verify / set-password steps.
    func challengeTokenExpiry(issuedAt: Date, onExpired: @escaping () -> Void) -> some View {
        modifier(ChallengeTokenExpiryModifier(issuedAt: issuedAt, onExpired: onExpired))
    }
}

#endif
