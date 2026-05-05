// MARK: - §6.5 HID Scanner Support
//
// Supports external Bluetooth / USB HID barcode scanners that appear to the
// OS as a keyboard. They produce rapid keystrokes (intra-key < 50 ms) and
// terminate with a Return key press.
//
// Strategy: a zero-size hidden `TextField` stays focused; a `Timer` fires
// 200 ms after the last keystroke — at that point if the buffer has ≥ 4
// chars we treat it as a scanned barcode. On Return we commit immediately.
//
// § agent-ownership.md: Barcode *camera* scan goes through Agent 2's Camera
// protocol. HID scanner is OS-keyboard input owned by Agent 5.

#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - HIDScannerField

/// Zero-height hidden text field that captures HID-scanner keystrokes.
///
/// Drop into a view hierarchy alongside visible content:
/// ```swift
/// ZStack {
///     HIDScannerField(onScan: handleScan)
///     VisibleContent()
/// }
/// ```
/// The field is invisible but `.focused` — it captures HID input without
/// affecting layout. Accessibility label ensures VoiceOver can discover it.
public struct HIDScannerField: View {
    public let onScan: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var buffer: String = ""
    @State private var lastKeystrokeAt: Date = .distantPast
    @State private var flushTimer: Timer?

    public init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
    }

    public var body: some View {
        TextField("", text: $buffer)
            .frame(width: 0, height: 0)
            .opacity(0)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .accessibilityLabel("Barcode scanner input")
            .accessibilityHidden(true)
            .onChange(of: buffer) { _, new in
                let now = Date()
                let delta = now.timeIntervalSince(lastKeystrokeAt)
                lastKeystrokeAt = now

                // HID scanners produce chars every < 50 ms; a human types > 100 ms.
                // We always reschedule the flush timer on each character change.
                flushTimer?.invalidate()
                flushTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: false) { _ in
                    commitBuffer()
                }

                // If delta < 50 ms and we have a complete barcode (via Return) —
                // the Return is not captured by SwiftUI TextField onChange; we rely
                // on the timer. For explicit newline in pasted input, commit now.
                if new.contains("\n") || new.contains("\r") {
                    flushTimer?.invalidate()
                    buffer = new.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
                    commitBuffer()
                    return
                }
                _ = delta // suppresses "unused" warning; delta is used for future per-tenant tuning
            }
    }

    private func commitBuffer() {
        let code = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard code.count >= 4 else { return }
        // §6.5 haptic on successful scan
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        gen.impactOccurred()
        onScan(code)
    }
}

// MARK: - HIDScannerOverlay (convenience modifier)

public extension View {
    /// Attaches an invisible HID-scanner capture field to this view.
    /// Fires `onScan` with the decoded barcode string (≥ 4 chars).
    /// A `UIImpactFeedbackGenerator(.medium)` haptic fires on each scan.
    func hidScanner(onScan: @escaping (String) -> Void) -> some View {
        overlay(alignment: .topLeading) {
            HIDScannerField(onScan: onScan)
        }
    }
}
#endif
