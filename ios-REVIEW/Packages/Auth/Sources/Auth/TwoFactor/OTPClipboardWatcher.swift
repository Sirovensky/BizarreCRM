#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - OTPClipboardWatcher
//
// §2.2 — Paste-from-clipboard auto-detect: monitors UIPasteboard for a
// 6-digit numeric string and auto-fills the bound `code` when one is found.
//
// Design choices:
// - Polling (app active transitions) rather than a timer — battery-friendly.
// - Only auto-fills when the field is empty (don't clobber user input).
// - Fires once per clipboard content change (tracks change count).
// - Does NOT clear clipboard immediately — that's handled by OTPPasteboardCleaner.

private struct OTPClipboardWatcherModifier: ViewModifier {
    @Binding var code: String
    @State private var lastChangeCount: Int = UIPasteboard.general.changeCount

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                checkClipboard()
            }
            // Also check on appear in case the user copy-pasted while the sheet was open.
            .onAppear { checkClipboard() }
    }

    private func checkClipboard() {
        let current = UIPasteboard.general.changeCount
        guard current != lastChangeCount || code.isEmpty else { return }
        lastChangeCount = current

        guard let raw = UIPasteboard.general.string else { return }
        let digits = raw.filter(\.isNumber)

        // Accept exactly 6 digits — common OTP shape.
        guard digits.count == 6, digits == raw.trimmingCharacters(in: .whitespaces) else { return }
        // Only auto-fill when the field is empty — don't clobber what the user typed.
        guard code.isEmpty else { return }

        code = digits
        // Schedule pasteboard clear after 30s (§2.13 policy).
        OTPPasteboardCleaner.scheduleWipe()
    }
}

public extension View {
    /// Watches the system clipboard for a 6-digit OTP and auto-fills `code`.
    /// Respects the §2.13 30-second pasteboard clear policy.
    func otpClipboardAutoFill(code: Binding<String>) -> some View {
        modifier(OTPClipboardWatcherModifier(code: code))
    }
}

#endif
