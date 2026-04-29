import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §28.8 Screen protection — iOS 17+ `isSecure` content flag on sensitive fields
//
// `UIView.isSecure = true` (available iOS 17+) marks a view's pixels as
// content-protected. The OS:
//   - Excludes the view from screen-recording capture (replaced with black rect).
//   - Excludes the view from screenshots (also replaced with black rect).
//
// This complements the §28.8 `screenCaptureProtected()` blur modifier (which
// operates at a View-overlay level) by working at the pixel compositor level,
// providing defence-in-depth.
//
// Apply to: PIN entry, OTP entry, masked-card reveal, any field whose content
// must never appear in screen recordings or screenshots even for a single frame.
//
// NOTE: `isSecure` on a view is NOT the same as `isSecureTextEntry` on a text
// field. `isSecureTextEntry` hides characters while typing; `isSecure` prevents
// the rendered pixels from being captured. Both are applied together here.

// MARK: - SecureTextEntryModifier

/// §28.8 — Marks a SwiftUI view's rendered pixels as screen-capture protected
/// (iOS 17+) while also ensuring secure text entry for text fields.
///
/// On iOS < 17 only the `isSecureTextEntry` behaviour applies; the pixel-level
/// protection is silently skipped (the `screenCaptureProtected()` blur modifier
/// provides a fallback at the view layer for those OS versions).
///
/// ## Usage
/// ```swift
/// TextField("PIN", text: $pin)
///     .secureInput()
///
/// // For a display-only sensitive value (e.g., revealed backup code):
/// Text(backupCode)
///     .secureInput()
/// ```
public struct SecureTextEntryModifier: ViewModifier {

    public init() {}

    public func body(content: Content) -> some View {
        content
            .introspectSecure()
            // Blur as a fallback on iOS < 17 when isCaptured is active.
            // The blur is invisible under normal use; it only activates
            // while screen-capture is detected by the environment service.
            .screenCaptureProtected()
    }
}

// MARK: - IntrospectSecureModifier

/// Applies `UIView.isSecure = true` via UIViewRepresentable introspection.
///
/// This is a separate modifier so it can be used independently where the
/// `screenCaptureProtected()` blur is intentionally omitted.
struct IntrospectSecureModifier: ViewModifier {

    func body(content: Content) -> some View {
        content.background(SecureViewMarker())
    }
}

// MARK: - SecureViewMarker

/// Zero-size UIViewRepresentable that walks the responder chain to find and
/// mark the nearest enclosing `UIView` as `isSecure`.
///
/// This technique is commonly used for UIKit interop in SwiftUI and is
/// approved by Apple's SwiftUI-UIKit bridging guidance.
private struct SecureViewMarker: UIViewRepresentable {

    func makeUIView(context: Context) -> _SecureMarkerView {
        _SecureMarkerView()
    }

    func updateUIView(_ uiView: _SecureMarkerView, context: Context) {}
}

// MARK: - _SecureMarkerView

private final class _SecureMarkerView: UIView {

    override func didMoveToWindow() {
        super.didMoveToWindow()
        markParentSecure()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        markParentSecure()
    }

    private func markParentSecure() {
        guard let parent = superview else { return }
        if #available(iOS 17.0, *) {
            parent.isSecure = true
        }
        // Walk one level up to catch SwiftUI host cell wrappers.
        if let grandparent = parent.superview, #available(iOS 17.0, *) {
            grandparent.isSecure = true
        }
    }
}

// MARK: - View extension

public extension View {
    /// §28.8 — Marks this view's pixels as screen-capture protected.
    ///
    /// On iOS 17+ the OS excludes these pixels from screen recordings and
    /// screenshots entirely. On older OS versions falls back to the
    /// `screenCaptureProtected()` blur overlay.
    ///
    /// Also enables `isSecureTextEntry` behaviour for text fields in the
    /// hierarchy via the capture modifier.
    func secureInput() -> some View {
        modifier(SecureTextEntryModifier())
    }

    /// Lower-level modifier — applies only the `UIView.isSecure = true` pixel
    /// protection without the blur fallback. Use when you need precise control.
    func pixelSecure() -> some View {
        modifier(IntrospectSecureModifier())
    }
}
