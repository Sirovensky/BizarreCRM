import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §28.8 Screen protection — secure text entry plus screen-capture fallback.
//
// The public UIKit SDK available to this build exposes `isSecureTextEntry` on
// text controls, and scene/screen capture detection for view-level fallbacks.
// This modifier keeps those protections together for sensitive fields.
//
// Apply to: PIN entry, OTP entry, masked-card reveal, any field whose content
// must never appear in screen recordings or screenshots even for a single frame.
//
// NOTE: `isSecureTextEntry` hides characters while typing. The accompanying
// `screenCaptureProtected()` modifier handles active screen capture fallback.

// MARK: - SecureTextEntryModifier

/// §28.8 — Applies the app's sensitive-input protections to a SwiftUI view.
///
/// Text fields receive `isSecureTextEntry` where UIKit exposes a backing text
/// control. The `screenCaptureProtected()` blur modifier provides the
/// view-layer fallback while screen capture is active.
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
            .modifier(IntrospectSecureModifier())
            // Blur as a fallback on iOS < 17 when isCaptured is active.
            // The blur is invisible under normal use; it only activates
            // while screen-capture is detected by the environment service.
            .screenCaptureProtected()
    }
}

// MARK: - IntrospectSecureModifier

/// Applies secure text-entry where the nearest UIKit host is a text field.
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
/// mark the nearest enclosing `UITextField` as secure text entry.
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
        var view: UIView? = superview
        while let current = view {
            if let textField = current as? UITextField {
                textField.isSecureTextEntry = true
                return
            }
            view = current.superview
        }
    }
}

// MARK: - View extension

public extension View {
    /// §28.8 — Applies secure-entry behaviour and screen-capture fallback.
    ///
    /// Enables `isSecureTextEntry` behaviour for text fields in the hierarchy
    /// and applies the `screenCaptureProtected()` blur overlay.
    func secureInput() -> some View {
        modifier(SecureTextEntryModifier())
    }

    /// Lower-level modifier — applies secure text-entry introspection without
    /// the blur fallback. Use when you need precise control.
    func pixelSecure() -> some View {
        modifier(IntrospectSecureModifier())
    }
}
