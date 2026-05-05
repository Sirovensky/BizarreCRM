import SwiftUI
import GameController
import DesignSystem

// MARK: - HardwareKeyboardDetector

/// Detects whether a hardware keyboard is currently attached via
/// `GCKeyboard.coalesced` and the `GCKeyboardDidConnectNotification` /
/// `GCKeyboardDidDisconnectNotification` system notifications.
///
/// - When attached: on-screen keyboard hints are suppressed and a floating
///   "Press ⌘/ for shortcuts" hint is offered.
/// - iPad-only by default; iPhone shows the hint only when a hardware
///   keyboard is detected (which suppresses the soft keyboard).
///
/// Usage:
/// ```swift
/// @State private var detector = HardwareKeyboardDetector()
///
/// var body: some View {
///     MyView()
///         .overlay(alignment: .bottom) {
///             if detector.isAttached {
///                 ShortcutHintPill()
///             }
///         }
/// }
/// ```
@Observable
@MainActor
public final class HardwareKeyboardDetector {

    // MARK: - Public state

    /// `true` when a hardware (external) keyboard is currently connected.
    public private(set) var isAttached: Bool = false

    // MARK: - Init

    public init() {
        // Snapshot the current state immediately.
        isAttached = GCKeyboard.coalesced != nil

        // Subscribe to connect / disconnect notifications so the property
        // updates reactively while the detector is alive.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidConnect(_:)),
            name: .GCKeyboardDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidDisconnect(_:)),
            name: .GCKeyboardDidDisconnect,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notification handlers

    @objc private func keyboardDidConnect(_ notification: Notification) {
        isAttached = true
    }

    @objc private func keyboardDidDisconnect(_ notification: Notification) {
        isAttached = GCKeyboard.coalesced != nil
    }
}

// MARK: - ShortcutHintPill

/// Floating "Press ⌘/ for shortcuts" badge shown when hardware keyboard
/// is detected. Placed at the bottom of the screen so it doesn't collide
/// with tab bars on iPad.
///
/// - Respects Reduce Motion: uses a simple fade instead of slide-in.
/// - Tapping the pill triggers `onTap` so the caller can toggle the overlay
///   without the pill needing a direct binding.
public struct ShortcutHintPill: View {
    public var onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onTap: @escaping () -> Void = {}) {
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            Label("Press ⌘/ for shortcuts", systemImage: "keyboard")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
        }
        .brandGlass(.clear, in: Capsule())
        .accessibilityLabel("Show keyboard shortcuts. Press Command Slash.")
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                  )
        )
    }
}
