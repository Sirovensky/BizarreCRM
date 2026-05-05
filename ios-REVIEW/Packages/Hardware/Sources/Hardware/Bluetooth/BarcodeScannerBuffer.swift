import Foundation
import Core

// MARK: - BarcodeScannerBuffer
//
// §17.2 — Barcode scanner keystroke buffer (HID wedge / external scanner).
//
// External USB or Bluetooth HID barcode scanners appear to iOS as a keyboard.
// They emit barcode digits as a rapid burst of keystrokes ending with a carriage
// return (0x0D / \r). The existing `ExternalScannerHIDListener` actor handles the
// raw HID interception; this actor is its deliberate debounce / accumulation layer:
//
//   HIDSinkTextField keystroke event
//     → ExternalScannerHIDListener
//       → BarcodeScannerBuffer.append(_:)
//         (debounce window: `windowDuration`, default 80 ms)
//       → [fires delegate/stream with accumulated barcode string]
//
// Why a separate buffer?
//   - Prevents partial scans reaching the lookup logic when a scanner is slow or
//     the host is under CPU pressure.
//   - Accumulates multi-character bursts arriving over several runloop ticks into a
//     single atomic string before notifying consumers.
//   - Provides a configurable `maximumLength` guard so runaway input cannot flood
//     the lookup pipeline.
//   - Separates concurrency/timing policy from the HID event source, making both
//     independently testable.
//
// Thread safety: `actor` isolation. Callers may `append` from any context.
// The delegate callback is always delivered on `@MainActor`.

// MARK: - BarcodeScannerBufferDelegate

/// Receives complete barcode strings once the accumulation window closes.
public protocol BarcodeScannerBufferDelegate: AnyObject, Sendable {
    /// Called on `@MainActor` when a complete barcode has been accumulated.
    @MainActor func scannerBuffer(_ buffer: BarcodeScannerBuffer, didScan barcode: String)
}

// MARK: - BarcodeScannerBuffer

/// Accumulates HID keystroke characters into complete barcode strings.
///
/// The buffer fires the delegate after `windowDuration` of silence following the
/// last appended character. A carriage-return character (`\r`) immediately flushes
/// the buffer — hardware scanners append CR after the last barcode digit.
///
/// Usage:
/// ```swift
/// let buffer = BarcodeScannerBuffer(delegate: self)
/// buffer.append("4")
/// buffer.append("2")
/// buffer.append("0")
/// buffer.append("\r")  // triggers immediate flush → "420" delivered to delegate
/// ```
public actor BarcodeScannerBuffer {

    // MARK: - Configuration

    /// Time window after the last character before the buffer auto-flushes.
    /// Default 80 ms — enough for slow USB HID on a loaded iPad.
    public let windowDuration: Duration

    /// Maximum barcode length accepted. Characters beyond this are discarded
    /// and the buffer is cleared (guards against stuck keys / runaway input).
    public let maximumLength: Int

    // MARK: - State

    private var accumulated: String = ""
    private var flushTask: Task<Void, Never>?
    private weak var delegate: (any BarcodeScannerBufferDelegate)?

    // MARK: - Init

    public init(
        delegate: any BarcodeScannerBufferDelegate,
        windowDuration: Duration = .milliseconds(80),
        maximumLength: Int = 128
    ) {
        self.delegate = delegate
        self.windowDuration = windowDuration
        self.maximumLength = maximumLength
    }

    // MARK: - Public API

    /// Append a single character (or short string) from a HID keystroke event.
    ///
    /// - If the string contains `\r` or `\n` the buffer flushes immediately.
    /// - Otherwise the debounce timer is reset to `windowDuration`.
    public func append(_ characters: String) {
        let hasTerminator = characters.contains("\r") || characters.contains("\n")

        let payload = characters
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        if !payload.isEmpty { accumulated += payload }

        if hasTerminator {
            flushTask?.cancel()
            flushNow()
            return
        }

        // Guard against runaway input.
        if accumulated.count > maximumLength {
            AppLog.hardware.warning("BarcodeScannerBuffer: input exceeded maximumLength (\(self.maximumLength)); discarding")
            accumulated = ""
            flushTask?.cancel()
            flushTask = nil
            return
        }

        // Restart the debounce window.
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: windowDuration)
                await self.flushNow()
            } catch {
                // Task cancelled — another character arrived; do nothing.
            }
        }
    }

    /// Immediately discard all accumulated characters without firing the delegate.
    public func clear() {
        accumulated = ""
        flushTask?.cancel()
        flushTask = nil
    }

    /// Programmatically flush the buffer (useful for testing or forced scans).
    public func flush() {
        flushTask?.cancel()
        flushNow()
    }

    // MARK: - Private

    private func flushNow() {
        let barcode = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        accumulated = ""
        flushTask = nil
        guard !barcode.isEmpty else { return }
        AppLog.hardware.info("BarcodeScannerBuffer: flushed '\(barcode, privacy: .public)' (\(barcode.count) chars)")
        guard let delegate else { return }
        Task { @MainActor [delegate] in
            delegate.scannerBuffer(self, didScan: barcode)
        }
    }
}

// MARK: - AsyncStream convenience

extension BarcodeScannerBuffer {

    /// Adapts `BarcodeScannerBuffer` to an `AsyncStream<String>` for contexts that
    /// prefer structured concurrency over delegation.
    ///
    /// ```swift
    /// let (stream, buffer) = BarcodeScannerBuffer.makeStream()
    /// Task {
    ///     for await barcode in stream {
    ///         await handle(barcode)
    ///     }
    /// }
    /// buffer.append("4006381333931")
    /// buffer.append("\r")
    /// ```
    public static func makeStream(
        windowDuration: Duration = .milliseconds(80),
        maximumLength: Int = 128
    ) -> (AsyncStream<String>, BarcodeScannerBuffer) {
        var continuation: AsyncStream<String>.Continuation!
        let stream = AsyncStream<String> { cont in continuation = cont }
        let adapter = AsyncBufferAdapter(continuation: continuation)
        let buffer = BarcodeScannerBuffer(
            delegate: adapter,
            windowDuration: windowDuration,
            maximumLength: maximumLength
        )
        return (stream, buffer)
    }
}

// MARK: - AsyncBufferAdapter (private)

/// Bridges `BarcodeScannerBufferDelegate` to an `AsyncStream<String>` continuation.
private final class AsyncBufferAdapter: BarcodeScannerBufferDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<String>.Continuation

    init(continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }

    @MainActor
    func scannerBuffer(_ buffer: BarcodeScannerBuffer, didScan barcode: String) {
        continuation.yield(barcode)
    }
}
