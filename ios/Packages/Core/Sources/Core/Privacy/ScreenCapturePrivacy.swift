import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §28 Security & Privacy helpers — Screen-capture detection service

// MARK: - ScreenCapturePrivacyProtocol

/// Abstraction over ``ScreenCapturePrivacy`` to enable test injection.
public protocol ScreenCapturePrivacyProtocol: AnyObject {
    /// `true` when the screen is currently being mirrored or recorded.
    @MainActor var isCaptured: Bool { get }
}

// MARK: - ScreenCapturePrivacy

/// Observable service that tracks whether the screen is currently being
/// captured (mirrored, AirPlayed, or screen-recorded).
///
/// Sensitive views should observe ``isCaptured`` and overlay a blur or
/// redaction layer when it is `true`.
///
/// ## Design
/// - Reads `UIScreen.isCaptured` for the initial state.
/// - Listens to `UIScreen.capturedDidChangeNotification` via `NotificationCenter`
///   so it never polls.
/// - Marked `@Observable` for direct use in SwiftUI `@State` / `@Environment`.
///
/// ## Usage
/// ```swift
/// @Environment(ScreenCapturePrivacy.self) private var capturePrivacy
///
/// var body: some View {
///     if capturePrivacy.isCaptured { RedactedOverlay() }
/// }
/// ```
///
/// ## Testing
/// Inject a ``MockScreenCapturePrivacy`` instead of the real service.
@Observable
@MainActor
public final class ScreenCapturePrivacy: ScreenCapturePrivacyProtocol, @unchecked Sendable {

    // MARK: - Observable state

    /// `true` when the main screen is currently being captured.
    public private(set) var isCaptured: Bool = false

    // MARK: - Private state

    nonisolated(unsafe) private var observerToken: Any?

    // MARK: - Init

    public init() {
        #if canImport(UIKit)
        self.isCaptured = UIScreen.main.isCaptured
        self.observerToken = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: UIScreen.main,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.isCaptured = UIScreen.main.isCaptured
            }
        }
        #endif
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

// MARK: - ScreenCaptureBlurModifier

/// §28.8 — Swaps sensitive view content for a blurred placeholder when the
/// screen is being mirrored or recorded (`UIScreen.isCaptured == true`).
///
/// Required on payment, 2FA, credentials-reveal, PIN-entry, and audit-export screens.
/// Customer-facing display (§16) should NOT use this modifier.
///
/// Usage:
/// ```swift
/// SensitivePaymentView()
///     .screenCaptureProtected()
/// ```
///
/// Injects a ``ScreenCapturePrivacy`` instance from the environment if present;
/// falls back to its own local instance when attached to a view that is not
/// a child of the main RootView environment.
public struct ScreenCaptureBlurModifier: ViewModifier {
    @Environment(ScreenCapturePrivacy.self) private var capturePrivacy: ScreenCapturePrivacy?
    @State private var localPrivacy = ScreenCapturePrivacy()

    public init() {}

    private var isCaptured: Bool {
        (capturePrivacy ?? localPrivacy).isCaptured
    }

    public func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: isCaptured ? 20 : 0)
                .allowsHitTesting(!isCaptured)

            if isCaptured {
                captureBlockerOverlay
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isCaptured) // §67 snappy = 220ms
    }

    @ViewBuilder
    private var captureBlockerOverlay: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Screen recording active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            )
    }
}

// MARK: - View extension

public extension View {
    /// Applies the §28.8 screen-capture blur protection to sensitive views.
    ///
    /// Blurs content and overlays a privacy placeholder while
    /// `UIScreen.main.isCaptured` is `true` (screen recording / AirPlay mirror).
    func screenCaptureProtected() -> some View {
        modifier(ScreenCaptureBlurModifier())
    }
}

// MARK: - MockScreenCapturePrivacy

/// Test double for ``ScreenCapturePrivacy``.
///
/// Set ``isCaptured`` directly to simulate screen-capture state changes.
@Observable
@MainActor
public final class MockScreenCapturePrivacy: ScreenCapturePrivacyProtocol, @unchecked Sendable {
    public var isCaptured: Bool

    public init(isCaptured: Bool = false) {
        self.isCaptured = isCaptured
    }

    /// Simulates a `UIScreen.capturedDidChangeNotification` by toggling
    /// ``isCaptured`` and posting the real notification for integration tests.
    public func simulateCaptureChange(isCaptured: Bool) {
        self.isCaptured = isCaptured
        #if canImport(UIKit)
        NotificationCenter.default.post(
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        #endif
    }
}
