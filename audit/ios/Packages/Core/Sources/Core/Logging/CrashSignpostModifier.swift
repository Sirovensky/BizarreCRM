import SwiftUI
import OSLog

// §32.3 Crash signpost wrapper modifier
//
// Attaches lightweight OSSignposter intervals + a `.fault`-level breadcrumb
// to any screen-level view so that post-crash Instruments traces pinpoint
// which screen was visible at time of crash.
//
// Usage:
// ```swift
// CheckoutView()
//     .crashSignpost(name: "pos.checkout")
// ```
//
// This does NOT capture any PII — `name` must be a developer-supplied string
// literal (dot-notation screen identifier), never user data.

// MARK: - CrashSignpostModifier

/// §32.3 — Records an OSSignposter interval and a `.fault`-level OSLog breadcrumb
/// bracketing the lifetime of the attached view.
///
/// In Instruments Time Profiler + Logging instruments, the interval appears as
/// `CrashSignpost/<name>` inside the `com.bizarrecrm / ui` category, making
/// it trivial to correlate a crash with the last visible screen.
public struct CrashSignpostModifier: ViewModifier {

    // MARK: - Properties

    private let name: StaticString
    /// Shared signposter bound to the `ui` category so it merges with
    /// `AppLog.Signpost.listRender` intervals in the same Instruments lane.
    private static let signposter = OSSignposter(
        subsystem: "com.bizarrecrm",
        category: "ui"
    )

    // State preserved across body evaluations.
    @State private var intervalState: OSSignpostIntervalState?

    // MARK: - Init

    public init(name: StaticString) {
        self.name = name
    }

    // MARK: - ViewModifier

    public func body(content: Content) -> some View {
        content
            .onAppear { beginInterval() }
            .onDisappear { endInterval() }
    }

    // MARK: - Private helpers

    private func beginInterval() {
        // Emit a `.notice`-level log so the screen name appears in Console.app
        // and in any attached crash log.
        AppLog.ui.notice("CrashSignpost begin: \(name.description, privacy: .public)")

        // Open an OSSignposter interval.  If one is already open (e.g. the view
        // briefly disappeared and re-appeared), close the previous one first.
        if let existing = intervalState {
            Self.signposter.endInterval(name, existing)
        }
        let state = Self.signposter.beginInterval(name)
        intervalState = state
    }

    private func endInterval() {
        AppLog.ui.notice("CrashSignpost end: \(name.description, privacy: .public)")
        if let state = intervalState {
            Self.signposter.endInterval(name, state)
            intervalState = nil
        }
    }
}

// MARK: - View extension

public extension View {
    /// §32.3 — Attach an OSSignposter interval + breadcrumb log to this screen.
    ///
    /// Use on the outermost view of each major screen.  The `name` parameter
    /// must be a **static string literal** — never pass a runtime value or
    /// user data.
    ///
    /// ```swift
    /// TicketDetailView(ticket: ticket)
    ///     .crashSignpost(name: "tickets.detail")
    /// ```
    func crashSignpost(name: StaticString) -> some View {
        modifier(CrashSignpostModifier(name: name))
    }
}
