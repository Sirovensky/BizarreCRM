#if canImport(UIKit)
import UIKit
#endif
import Foundation
import OSLog

// §29.6 Memory — flush image cache + Nuke memcache + GRDB page cache on
// `UIApplication.didReceiveMemoryWarningNotification` (line 4425).
//
// `MemoryWarningFlusher` is the central registration point. Domain packages
// register their own flush callbacks via `MemoryWarningFlusher.shared.register(_:)`.
// The app (or tests) call `start()` once; the flusher then fires all callbacks
// whenever the OS issues a memory warning.

/// Coordinates memory-pressure responses across packages.
///
/// Each package that holds a purgeable cache (image pipeline memory cache,
/// GRDB page cache, in-memory view-model caches) registers a closure:
///
/// ```swift
/// // In AppServices.init or package bootstrap:
/// MemoryWarningFlusher.shared.register {
///     ImagePipeline.shared.cache.removeAll()
/// }
/// ```
///
/// The flusher fires all callbacks serially on the main queue in response to
/// `UIApplication.didReceiveMemoryWarningNotification`. It also samples
/// resident memory via `MemoryProbe` before and after so the delta is visible
/// in the `AppLog.perf` stream.
@MainActor
public final class MemoryWarningFlusher {

    // MARK: - Shared instance

    public static let shared = MemoryWarningFlusher()

    // MARK: - Private

    private var handlers: [@Sendable () -> Void] = []
    private var observerToken: NSObjectProtocol?

    private init() {}

    // MARK: - Public API

    /// Registers `flush` to be called on every memory warning.
    ///
    /// - Parameter flush: A synchronous closure that empties one cache layer.
    ///   Must be safe to call on the main queue at any time.
    public func register(_ flush: @escaping @Sendable () -> Void) {
        handlers.append(flush)
    }

    /// Starts listening for `UIApplication.didReceiveMemoryWarningNotification`.
    ///
    /// Safe to call multiple times — only one observer is registered.
    public func start() {
        guard observerToken == nil else { return }

#if canImport(UIKit)
        observerToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.flush()
            }
        }
        AppLog.perf.info("[MemoryWarningFlusher] observer started; \(self.handlers.count, privacy: .public) handler(s) registered")
#endif
    }

    /// Stops listening. Existing handlers are retained; `start()` can re-arm.
    public func stop() {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
    }

    // MARK: - Private

    private func flush() {
        let beforeMB = MemoryProbe.currentResidentMB()
        AppLog.perf.info("[MemoryWarningFlusher] memory warning received; before=\(String(format: "%.1f", beforeMB), privacy: .public) MB")

        for handler in handlers {
            handler()
        }

        let afterMB = MemoryProbe.currentResidentMB()
        let deltaMB = beforeMB - afterMB
        AppLog.perf.info(
            "[MemoryWarningFlusher] flush complete; after=\(String(format: "%.1f", afterMB), privacy: .public) MB freed≈\(String(format: "%.1f", deltaMB), privacy: .public) MB"
        )
    }
}
