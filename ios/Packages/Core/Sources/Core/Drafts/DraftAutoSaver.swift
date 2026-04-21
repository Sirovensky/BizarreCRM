import Foundation

// §63 ext — Draft auto-save helper (Phase 2)
// Debounced save that coalesces rapid field changes into a single write.
// @MainActor because callers (ViewModels) are @MainActor.

/// A debounced auto-save shim that wraps `DraftStore.shared`.
///
/// Typical usage:
/// ```swift
/// private let autoSaver = DraftAutoSaver<MyDraft>(screen: "thing.create")
///
/// func onFieldChange() {
///     autoSaver.push(buildDraft())
/// }
/// ```
///
/// Every `push` schedules a save after `debounceSeconds` (default 10).
/// Calling `push` again before the deadline cancels the previous pending save.
@MainActor
public final class DraftAutoSaver<T: Codable & Sendable> {

    // MARK: — Configuration

    private let store: DraftStore
    private let screen: String
    private let entityId: String?
    private let debounceSeconds: TimeInterval

    // MARK: — State

    private var pending: Task<Void, Never>?

    // MARK: — Init

    /// - Parameters:
    ///   - screen:          Screen identifier (passed to `DraftStore`).
    ///   - entityId:        Optional entity id for edit flows.
    ///   - debounceSeconds: Seconds to wait before persisting. Default 10.
    ///   - store:           Injected for testing; defaults to `DraftStore()` (unique suite per init in tests).
    public init(
        screen: String,
        entityId: String? = nil,
        debounceSeconds: TimeInterval = 10,
        store: DraftStore = DraftStore()
    ) {
        self.screen = screen
        self.entityId = entityId
        self.debounceSeconds = debounceSeconds
        self.store = store
    }

    // MARK: — Public API

    /// Schedule a debounced save of `draft`.
    ///
    /// Calling this before the previous deadline fires cancels the previous task.
    public func push(_ draft: T) {
        pending?.cancel()
        let capturedStore = store
        let capturedScreen = screen
        let capturedEntityId = entityId
        let ns = UInt64(debounceSeconds * 1_000_000_000)
        pending = Task { [capturedStore, capturedScreen, capturedEntityId] in
            do {
                try await Task.sleep(nanoseconds: ns)
                try await capturedStore.save(draft, screen: capturedScreen, entityId: capturedEntityId)
            } catch is CancellationError {
                // Intentional cancel — no-op.
            } catch {
                AppLog.ui.error(
                    "DraftAutoSaver save failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Immediately cancel any pending debounced save and clear the stored draft.
    public func clear() async {
        pending?.cancel()
        pending = nil
        await store.clear(screen: screen, entityId: entityId)
    }

    /// Cancel any pending save without clearing the stored draft.
    /// Useful when navigating away but wanting to keep the draft for later recovery.
    public func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
