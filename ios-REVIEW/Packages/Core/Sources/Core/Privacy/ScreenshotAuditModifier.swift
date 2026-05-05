#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import OSLog

// §28.8 Screenshot detection — SwiftUI ergonomic wrapper for ScreenshotAuditCounter.
//
// Sensitive screens (payment, 2FA, audit-export, receipts containing PAN last4)
// must record a screenshot event whenever the user invokes the system shutter
// while looking at them. iOS does not let us *block* the screenshot — only
// observe it after the fact — so the contract is:
//
//   1. Record an audit entry (screen, user, timestamp).
//   2. Optionally show a one-shot informational banner ("Receipts contain
//      customer info — share carefully.") on opt-in screens.
//
// This file ships the SwiftUI modifier so domain code reads:
//
// ```swift
// PaymentReceiptView()
//     .screenshotAudited(
//         screen: "payment-receipt",
//         userID: session.userID,
//         onCapture: auditLogRepository.recordScreenshot
//     )
// ```
//
// The modifier owns a `ScreenshotAuditCounter` keyed to the View's lifetime,
// attaches it on `.onAppear`, detaches on `.onDisappear`. No global state.

// MARK: - ScreenshotAuditModifier

@MainActor
private struct ScreenshotAuditModifier: ViewModifier {

    let screen: String
    let userID: String?
    let onCapture: @Sendable (ScreenshotAuditEntry) -> Void

    @State private var counter = ScreenshotAuditCounter()

    func body(content: Content) -> some View {
        content
            .onAppear {
                counter.attach(
                    screenIdentifier: screen,
                    userID: userID,
                    onScreenshot: onCapture
                )
            }
            .onDisappear {
                counter.detach()
            }
    }
}

// MARK: - View extension

public extension View {

    /// Attach a screenshot audit observer to this View while it is on screen.
    ///
    /// Use on every "sensitive" screen per §28.8. The observer increments a
    /// counter and fires `onCapture` for each `userDidTakeScreenshotNotification`.
    /// Detached automatically on `.onDisappear`.
    ///
    /// - Parameters:
    ///   - screen:    Stable identifier (e.g. `"payment-receipt"`).
    ///   - userID:    Current user ID; `nil` on pre-auth screens.
    ///   - onCapture: Audit-log sink. Called on the main queue.
    @ViewBuilder
    func screenshotAudited(
        screen: String,
        userID: String?,
        onCapture: @escaping @Sendable (ScreenshotAuditEntry) -> Void
    ) -> some View {
        modifier(ScreenshotAuditModifier(
            screen: screen,
            userID: userID,
            onCapture: onCapture
        ))
    }

    /// Convenience overload — logs the entry to OSLog (`com.bizarrecrm`,
    /// category `screenshotAudit`) at `.notice` so it lands in diagnostics
    /// bundles without needing a server-side audit-log writer.
    ///
    /// Use this on screens where the audit-log writer hasn't been wired yet
    /// (still beats no observation at all).
    @ViewBuilder
    func screenshotAuditedToLog(
        screen: String,
        userID: String?
    ) -> some View {
        modifier(ScreenshotAuditModifier(
            screen: screen,
            userID: userID,
            onCapture: ScreenshotAuditLogSink.write
        ))
    }
}

// MARK: - ScreenshotAuditLogSink

/// Default OSLog sink used by `screenshotAuditedToLog`. Marked
/// `.notice` so it persists into sysdiagnose bundles. The user ID is logged
/// `.private` per §28.7 redaction contract.
public enum ScreenshotAuditLogSink {

    private static let log = Logger(subsystem: "com.bizarrecrm", category: "screenshotAudit")

    public static func write(_ entry: ScreenshotAuditEntry) {
        let safeScreen = entry.screenIdentifier
        let safeUser   = entry.userID ?? "<anonymous>"
        let isoDate    = ISO8601DateFormatter().string(from: entry.timestamp)
        log.notice("Screenshot taken: screen=\(safeScreen, privacy: .public) user=\(safeUser, privacy: .private) at=\(isoDate, privacy: .public)")
    }
}

#endif
