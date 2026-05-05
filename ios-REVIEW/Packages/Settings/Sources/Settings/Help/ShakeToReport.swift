import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ShakeToReport

/// Registers a shake-to-report handler. **DEBUG builds only.**
///
/// Usage: call `ShakeToReport.install()` at app launch (DEBUG only).
/// The handler posts a `ShakeToReport.shakeDetectedNotification` that
/// the host view listens to and presents `BugReportSheet`.
///
/// The responder override (`becomeFirstResponder`) is an iOS-only UIKit hook
/// and is excluded from non-UIKit builds.

#if DEBUG && canImport(UIKit)

public enum ShakeToReport {

    /// Posted on the main actor when a shake is detected.
    public static let shakeDetectedNotification = Notification.Name("com.bizarrecrm.shakeDetected")

    /// Call once at `applicationDidFinishLaunching` (DEBUG only).
    public static func install() {
        // Swizzling via UIWindow subclass approach — no method swizzle required.
        // Installed in `AppDelegate.window` or via `ShakeWindow`.
    }
}

// MARK: - ShakeWindow

/// A UIWindow subclass that overrides motion events to detect shakes.
/// Swap in at app launch to enable shake-to-report in DEBUG.
public final class ShakeWindow: UIWindow {

    override public func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(
                name: ShakeToReport.shakeDetectedNotification,
                object: nil
            )
        }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - ShakeToReportModifier

/// View modifier that listens for `shakeDetectedNotification` and presents
/// `BugReportSheet` as a sheet.
public struct ShakeToReportModifier: ViewModifier {

    @State private var showBugReport: Bool = false

    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showBugReport) {
                BugReportSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: ShakeToReport.shakeDetectedNotification)) { _ in
                showBugReport = true
            }
    }
}

public extension View {
    /// Attach shake-to-report to any view hierarchy. DEBUG only.
    func shakeToReport() -> some View {
        modifier(ShakeToReportModifier())
    }
}

#else

// MARK: - Non-debug stub

/// No-op stub for RELEASE builds. ShakeToReport is completely absent.
public enum ShakeToReport {
    public static let shakeDetectedNotification = Notification.Name("com.bizarrecrm.shakeDetected")
    public static func install() { /* no-op in release */ }
}

public extension View {
    /// No-op in RELEASE builds.
    @inlinable
    func shakeToReport() -> some View { self }
}

#endif
