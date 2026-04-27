#if canImport(UIKit)
import UIKit
import Combine
import Core

// MARK: - ExternalScannerHIDListener
//
// §17.2 — "External scanners — MFi Socket Mobile / Zebra SDK integration;
//           scanner types as HID keyboard fallback."
//
// Most external barcode scanners (Socket Mobile, Honeywell, Zebra in HID mode)
// emulate a USB/Bluetooth keyboard. When connected to an iPad/iPhone via
// Lightning/USB-C or Bluetooth, they inject characters as if the user typed
// them, followed by a carriage-return (U+000D) or newline terminator.
//
// This listener intercepts that input by watching for rapid keystroke bursts
// on an invisible text field (the "HID sink"). A burst of ≥ 4 characters
// followed by a line-terminator within `burstWindowSeconds` is treated as a
// barcode scan and published via the `barcodePublisher`.
//
// Usage:
// ```swift
// let listener = ExternalScannerHIDListener()
// listener.barcodePublisher
//     .sink { barcode in handleBarcode(barcode) }
//     .store(in: &cancellables)
// // Embed hidSinkView somewhere in the responder chain.
// contentView.addSubview(listener.hidSinkView)
// listener.hidSinkView.becomeFirstResponder()
// ```
//
// Note: This approach does not require MFi or Socket Mobile SDK.
// The MFi SDK path (for full device management) is a separate integration
// deferred to MFi approval; this covers the common HID-keyboard mode.

// MARK: - ExternalScannerHIDListener

@MainActor
public final class ExternalScannerHIDListener {

    // MARK: - Configuration

    /// Minimum barcode length to be accepted (filters single-key presses).
    public var minimumLength: Int = 4
    /// Maximum seconds between characters to still be considered a single burst.
    public var burstWindowSeconds: TimeInterval = 0.08
    /// Line terminators used by HID scanners.
    private static let terminators: Set<Character> = ["\r", "\n"]

    // MARK: - Published barcode stream

    public let barcodePublisher: AnyPublisher<Barcode, Never>
    private let subject = PassthroughSubject<Barcode, Never>()

    // MARK: - HID sink view

    /// Add this view to your view hierarchy and call `becomeFirstResponder()`.
    public lazy var hidSinkView: HIDSinkTextField = HIDSinkTextField(listener: self)

    // MARK: - Private state

    private var buffer: String = ""
    private var lastKeystroke: Date = .distantPast

    // MARK: - Init

    public init() {
        barcodePublisher = subject.eraseToAnyPublisher()
    }

    // MARK: - Internal: called by HIDSinkTextField

    func receive(character: Character) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastKeystroke)

        // If too long since last keystroke, flush stale buffer.
        if elapsed > burstWindowSeconds && !buffer.isEmpty {
            buffer = ""
            AppLog.camera.debug("ExternalScannerHIDListener: burst timeout — buffer cleared")
        }
        lastKeystroke = now

        if Self.terminators.contains(character) {
            // Terminator received — emit if buffer meets minimum length.
            flushBuffer()
        } else {
            buffer.append(character)
            // Safety: cap buffer at 128 chars (no barcode is that long).
            if buffer.count > 128 {
                buffer = String(buffer.suffix(128))
            }
        }
    }

    private func flushBuffer() {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard trimmed.count >= minimumLength else {
            AppLog.camera.debug("ExternalScannerHIDListener: buffer too short (\(trimmed.count)) — discarded")
            return
        }
        let barcode = Barcode(value: trimmed, symbology: "hid")
        subject.send(barcode)
        AppLog.camera.info("ExternalScannerHIDListener: emitted HID barcode length=\(trimmed.count)")
    }
}

// MARK: - HIDSinkTextField

/// A zero-size, invisible text field that absorbs HID scanner input without
/// disrupting the visible UI. Add to the view hierarchy before presenting
/// the scanner so it can become first responder.
///
/// On iPad, this view can coexist with a DataScannerViewController — if the
/// physical camera scanner fires, the BarcodeScannerView handles it. If a
/// connected HID scanner fires, this view intercepts it.
public final class HIDSinkTextField: UITextField {

    private weak var listener: ExternalScannerHIDListener?

    init(listener: ExternalScannerHIDListener) {
        self.listener = listener
        super.init(frame: .zero)
        isHidden = true
        autocorrectionType = .no
        spellCheckingType = .no
        keyboardType = .asciiCapable
        // Disable the on-screen keyboard — HID scanner injects directly.
        inputView = UIView()  // empty view replaces system keyboard
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not implemented") }

    // Intercept text changes at the delegate level so we can process
    // characters individually before UIKit processes them normally.
    override public func insertText(_ text: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for char in text {
                await self.listener?.receive(character: char)
            }
        }
        // Do NOT call super — we consume the input here.
    }

    override public func deleteBackward() {
        // Ignore deletes from HID scanner (unusual but possible with bad firmware).
    }
}

extension HIDSinkTextField: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        Task { @MainActor [weak self] in
            await self?.listener?.receive(character: "\r")
        }
        return false
    }
}

// MARK: - SwiftUI Wrapper

import SwiftUI

/// SwiftUI `UIViewRepresentable` for embedding `HIDSinkTextField` in a SwiftUI
/// view hierarchy. Place it at the root of any view that should respond to HID
/// scanner input.
///
/// Usage:
/// ```swift
/// ZStack {
///     mainContent
///     HIDScannerListenerView(listener: myListener)
///         .frame(width: 0, height: 0)
/// }
/// ```
public struct HIDScannerListenerView: UIViewRepresentable {

    let listener: ExternalScannerHIDListener

    public init(listener: ExternalScannerHIDListener) {
        self.listener = listener
    }

    @MainActor
    public func makeUIView(context: Context) -> HIDSinkTextField {
        let field = listener.hidSinkView
        field.frame = .zero
        return field
    }

    public func updateUIView(_ uiView: HIDSinkTextField, context: Context) {}
}

#endif
