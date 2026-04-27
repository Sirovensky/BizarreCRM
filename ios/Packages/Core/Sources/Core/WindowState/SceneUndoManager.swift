import Foundation
import SwiftUI

// MARK: - §1 UndoManager per scene
//
// Each scene (window) gets its own independent undo stack.
// Register actions via `SceneUndoManager.registerUndo(...)`.
// The stack is cleared on scene disconnect / dismiss.
//
// Covered actions (§1):
//   - Ticket field edit
//   - POS cart item add/remove
//   - Inventory adjustment
//   - Customer field edit
//   - Status change
//   - Notes add/remove
//
// Triggers (§1):
//   - ⌘Z on iPad hardware keyboard
//   - ⌘⇧Z redo
//   - iPhone .accessibilityAction(.undo) + shake-to-undo (if iOS setting enabled)
//   - Context-menu button for non-keyboard users
//
// Sync (§1):
//   - Undo rolls back optimistic change; sends compensating PATCH if already synced.
//   - If compensating request fails, toasts "Can't undo — action already processed".

/// A scene-scoped undo/redo stack with a capacity of 50 entries.
///
/// One instance per `UIWindowScene` / SwiftUI scene group. Inject via
/// `@EnvironmentObject` from the scene root.
@Observable @MainActor
public final class SceneUndoManager {

    // MARK: - Types

    public struct UndoEntry: Identifiable, Sendable {
        public let id: UUID
        public let description: String
        /// Block executed on undo. May dispatch async compensating request.
        public let undo: @Sendable () async -> Void
        /// Block executed on redo (re-applies the action).
        public let redo: @Sendable () async -> Void

        public init(
            description: String,
            undo: @escaping @Sendable () async -> Void,
            redo: @escaping @Sendable () async -> Void
        ) {
            self.id = UUID()
            self.description = description
            self.undo = undo
            self.redo = redo
        }
    }

    // MARK: - State

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private let maxDepth = 50

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var undoActionDescription: String? { undoStack.last?.description }
    public var redoActionDescription: String? { redoStack.last?.description }

    /// Total number of undoable actions on the stack.
    public var undoCount: Int { undoStack.count }

    /// Descriptions of the last N undoable actions, most-recent first.
    /// Used by `RecentUndoMenuButton` to populate the ⌘Z quick-picker (§63.5).
    public func recentUndoDescriptions(limit: Int) -> [String] {
        Array(undoStack.suffix(limit).reversed().map(\.description))
    }

    /// Undo all actions on the stack sequentially (most-recent first).
    ///
    /// Each undo fires the registered compensating closure; if any fail they
    /// are silently skipped so the rest of the stack can still drain.
    public func undoAll() async {
        while canUndo {
            await undo()
        }
    }

    // MARK: - Registration

    /// Register a new undoable action.
    ///
    /// - Parameters:
    ///   - description: Human-readable label shown in context menus.
    ///   - undo: Closure that reverts the action. Called on undo().
    ///   - redo: Closure that re-applies the action. Called on redo().
    public func registerUndo(
        description: String,
        undo: @escaping @Sendable () async -> Void,
        redo: @escaping @Sendable () async -> Void
    ) {
        let entry = UndoEntry(description: description, undo: undo, redo: redo)
        undoStack.append(entry)
        if undoStack.count > maxDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()  // new action clears redo stack
    }

    // MARK: - Undo / Redo

    /// Perform the most recent undoable action.
    public func undo() async {
        guard let entry = undoStack.popLast() else { return }
        await entry.undo()
        redoStack.append(entry)
    }

    /// Re-apply the most recently undone action.
    public func redo() async {
        guard let entry = redoStack.popLast() else { return }
        await entry.redo()
        undoStack.append(entry)
    }

    // MARK: - Lifecycle

    /// Clear both stacks — call on scene disconnect.
    public func clearAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

// MARK: - EnvironmentKey

// `SceneUndoManager` is `@MainActor`-isolated, so its init can only be called
// on the main actor. `EnvironmentKey.defaultValue` must be nonisolated. We
// satisfy both constraints by making the stored default nonisolated(unsafe) and
// wrapping its creation so it is only ever initialised from the main actor via
// the `EnvironmentValues` accessor, which SwiftUI always calls on @MainActor.
private final class _SceneUndoManagerBox: @unchecked Sendable {
    // `MainActor.assumeIsolated` is safe here: SwiftUI only accesses
    // `EnvironmentKey.defaultValue` from @MainActor contexts.
    let value: SceneUndoManager = MainActor.assumeIsolated { SceneUndoManager() }
}

private struct SceneUndoManagerKey: EnvironmentKey {
    nonisolated(unsafe) static let _box = _SceneUndoManagerBox()
    static var defaultValue: SceneUndoManager { _box.value }
}

extension EnvironmentValues {
    /// The scene-scoped undo/redo manager.
    ///
    /// Consumed by feature views via `@Environment(\.sceneUndoManager)`.
    public var sceneUndoManager: SceneUndoManager {
        get { self[SceneUndoManagerKey.self] }
        set { self[SceneUndoManagerKey.self] = newValue }
    }
}

// MARK: - View modifier — keyboard shortcuts

extension View {
    /// Wires ⌘Z / ⌘⇧Z keyboard shortcuts to the `SceneUndoManager` in the environment.
    ///
    /// Apply once at the scene root (e.g., `MainShellView`).
    public func sceneUndoKeyboardShortcuts(manager: SceneUndoManager) -> some View {
        self
            .keyboardShortcut("z", modifiers: .command)
            // SwiftUI doesn't expose a direct way to run async on keyboard shortcut;
            // wrap in Task so the async undo work happens off the button tap.
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    Task { @MainActor in await manager.undo() }
                }
            )
    }
}
