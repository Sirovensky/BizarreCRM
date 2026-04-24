import Foundation

// §32 Telemetry Sovereignty Guardrails — actor-isolated event buffer

// MARK: - TelemetryBuffer

/// Actor-isolated buffer that accumulates `TelemetryRecord` events and flushes
/// them in batches to an injected `TelemetryFlusher`.
///
/// ## Flush triggers
///
/// 1. **Threshold flush** — when the buffer reaches `capacity` events, an
///    immediate flush is triggered.
/// 2. **Interval flush** — a `Task` fires every `flushInterval` seconds and
///    drains any pending events regardless of buffer size.
/// 3. **Manual flush** — callers invoke `flush()` directly (e.g., on
///    `scenePhase == .background`).
///
/// ## Error handling
///
/// If `flusher.flush(_:)` throws, the batch is **re-queued** at the front of the
/// buffer so events survive transient network failures. Repeated failures are
/// capped: if the buffer would exceed `capacity * 2`, the oldest events are
/// silently dropped to prevent unbounded memory growth.
///
/// ## Sovereignty
///
/// `TelemetryBuffer` imports only `Foundation`. It is unaware of the network
/// layer; the concrete `TelemetryFlusher` wires `APIClient` outside `Core`.
///
/// ## Usage
/// ```swift
/// let buffer = TelemetryBuffer(flusher: myFlusher)
/// await buffer.enqueue(.init(category: .auth, name: "auth.login.succeeded"))
/// await buffer.flush()   // call on app background
/// ```
public actor TelemetryBuffer {

    // MARK: - Configuration

    /// Maximum events to accumulate before an automatic flush.
    public let capacity: Int

    /// How often the periodic timer fires (seconds).
    public let flushInterval: TimeInterval

    // MARK: - State

    private var buffer: [TelemetryRecord] = []
    private let flusher: any TelemetryFlusher
    private var timerTask: Task<Void, Never>?

    // MARK: - Init

    /// Create a buffer.
    ///
    /// - Parameters:
    ///   - flusher: The app-shell-provided flusher. Must be `Sendable`.
    ///   - capacity: Batch size threshold (default 50).
    ///   - flushInterval: Periodic flush interval in seconds (default 60).
    ///   - startTimer: Pass `false` in unit tests to disable background timer.
    public init(
        flusher: any TelemetryFlusher,
        capacity: Int = 50,
        flushInterval: TimeInterval = 60,
        startTimer: Bool = true
    ) {
        self.flusher       = flusher
        self.capacity      = capacity
        self.flushInterval = flushInterval
        if startTimer {
            // Timer is started after init via a separate call to allow actor isolation.
        }
        // Store whether we should start the timer so `startPeriodicFlush` can be called.
        self._shouldStartTimer = startTimer
    }

    // Deferred timer-start flag (read once in `startPeriodicFlushIfNeeded`).
    private let _shouldStartTimer: Bool

    /// Called once by the app-shell (or automatically on first enqueue) to arm
    /// the periodic flush timer.  Safe to call multiple times — subsequent calls
    /// are no-ops.
    public func startPeriodicFlushIfNeeded() {
        guard _shouldStartTimer, timerTask == nil else { return }
        let interval = flushInterval
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.flush()
            }
        }
    }

    // MARK: - Public API

    /// Enqueue a single event. Triggers an immediate flush if `buffer.count >= capacity`.
    ///
    /// Properties are expected to be **pre-scrubbed** through `TelemetryRedactor`.
    public func enqueue(_ event: TelemetryRecord) async {
        buffer.append(event)
        startPeriodicFlushIfNeeded()
        if buffer.count >= capacity {
            await flush()
        }
    }

    /// Flush all buffered events immediately. No-op if the buffer is empty.
    ///
    /// On transport failure the batch is re-queued; events exceeding
    /// `capacity * 2` are discarded to prevent unbounded growth.
    public func flush() async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        do {
            try await flusher.flush(batch)
        } catch {
            // Re-queue failed batch at the front.
            buffer.insert(contentsOf: batch, at: 0)
            // Cap buffer to prevent unbounded growth on repeated failures.
            let maxRetained = capacity * 2
            if buffer.count > maxRetained {
                buffer.removeFirst(buffer.count - maxRetained)
            }
        }
    }

    /// Cancel the background timer. Call when the buffer is being torn down.
    public func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Current number of buffered events (for testing / diagnostics).
    public var pendingCount: Int { buffer.count }
}
