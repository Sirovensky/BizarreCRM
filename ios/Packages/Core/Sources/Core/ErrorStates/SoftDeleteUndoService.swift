import Foundation
import SwiftUI

// MARK: - §63.5 Soft-delete with undo toast
//
// Wraps any soft-delete operation in a 5-second undo window.
// Shows a BrandToast "Deleted. Undo?" with an Undo action.
// If the user does not undo within the window, the deletion is committed.
//
// Usage:
//   SoftDeleteUndoService.shared.performDelete(
//       label: "Ticket #1234",
//       softDelete: { await ticketRepository.archive(id: 1234) },
//       undo:       { await ticketRepository.restore(id: 1234) }
//   )

// MARK: - SoftDeleteUndoEntry

public struct SoftDeleteUndoEntry: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let undoWindow: TimeInterval

    let softDeleteTask: @Sendable () async -> Void
    let undoTask: @Sendable () async -> Void
    var isCancelled: Bool = false

    public init(
        label: String,
        undoWindow: TimeInterval = 5,
        softDelete: @escaping @Sendable () async -> Void,
        undo: @escaping @Sendable () async -> Void
    ) {
        self.id         = UUID()
        self.label      = label
        self.undoWindow = undoWindow
        self.softDeleteTask = softDelete
        self.undoTask   = undo
    }
}

// MARK: - SoftDeleteUndoService

/// Manages soft-delete operations with a timed undo window.
///
/// Inject via `@Environment(\.softDeleteUndoService)` or use `.shared` directly.
@Observable @MainActor
public final class SoftDeleteUndoService {

    public static let shared = SoftDeleteUndoService()

    // MARK: - State

    /// The active undo entry (if any). UI observes this to show the toast.
    public private(set) var activeEntry: SoftDeleteUndoEntry?

    // MARK: - Init

    public init() {}

    // MARK: - API

    /// Begin a soft-delete with an undo window.
    ///
    /// The `softDelete` closure is called immediately (optimistic UI).
    /// If the user taps Undo within `undoWindow` seconds, `undo` is called and
    /// `softDelete` is not committed.  After the window expires, the entry is
    /// cleared and the deletion stands.
    ///
    /// - Parameters:
    ///   - label: Human-readable entity label, e.g. "Ticket #1234".
    ///   - undoWindow: Seconds until the undo option expires (default 5).
    ///   - softDelete: Async closure that performs the optimistic delete.
    ///   - undo: Async closure that reverts the optimistic delete.
    public func performDelete(
        label: String,
        undoWindow: TimeInterval = 5,
        softDelete: @escaping @Sendable () async -> Void,
        undo: @escaping @Sendable () async -> Void
    ) {
        // Dismiss any currently active entry first (only one at a time)
        if let existing = activeEntry {
            commitDelete(existing)
        }

        let entry = SoftDeleteUndoEntry(
            label: label,
            undoWindow: undoWindow,
            softDelete: softDelete,
            undo: undo
        )

        // Perform optimistic soft-delete immediately.
        Task { await softDelete() }

        activeEntry = entry

        // Schedule auto-commit after undo window.
        Task {
            try? await Task.sleep(for: .seconds(undoWindow))
            guard let current = activeEntry, current.id == entry.id, !current.isCancelled else { return }
            clearEntry()
            // Deletion already committed optimistically; nothing more to do.
        }
    }

    /// User tapped "Undo" — revert the deletion.
    public func performUndo() {
        guard var entry = activeEntry else { return }
        entry.isCancelled = true
        activeEntry = nil
        Task { await entry.undoTask() }
    }

    // MARK: - Helpers

    private func commitDelete(_ entry: SoftDeleteUndoEntry) {
        // Already committed optimistically — just clear UI state.
        activeEntry = nil
    }

    private func clearEntry() {
        activeEntry = nil
    }
}

// MARK: - EnvironmentKey

// `SoftDeleteUndoService.shared` is `@MainActor`-isolated. EnvironmentKey's
// `defaultValue` must be nonisolated. Use the same box pattern as
// `SceneUndoManagerKey` to avoid the Swift 6 actor-isolation error.
private final class _SoftDeleteBox: @unchecked Sendable {
    let value: SoftDeleteUndoService = MainActor.assumeIsolated { SoftDeleteUndoService.shared }
}

private struct SoftDeleteUndoServiceKey: EnvironmentKey {
    nonisolated(unsafe) static let _box = _SoftDeleteBox()
    static var defaultValue: SoftDeleteUndoService { _box.value }
}

extension EnvironmentValues {
    /// Scene-accessible soft-delete undo service.
    public var softDeleteUndoService: SoftDeleteUndoService {
        get { self[SoftDeleteUndoServiceKey.self] }
        set { self[SoftDeleteUndoServiceKey.self] = newValue }
    }
}

// MARK: - View modifier

extension View {
    /// Overlay a soft-delete undo toast managed by `SoftDeleteUndoService`.
    ///
    /// Apply once at the scene root so the toast appears above all content.
    ///
    ///     MainShellView()
    ///         .softDeleteUndoOverlay(service: SoftDeleteUndoService.shared)
    public func softDeleteUndoOverlay(service: SoftDeleteUndoService) -> some View {
        self.overlay(alignment: .bottom) {
            if let entry = service.activeEntry {
                SoftDeleteUndoToast(entry: entry, service: service)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: service.activeEntry?.id)
            }
        }
    }
}

// MARK: - SoftDeleteUndoToast

/// Glass chip shown during the undo window.
private struct SoftDeleteUndoToast: View {
    let entry: SoftDeleteUndoEntry
    let service: SoftDeleteUndoService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("\(entry.label) deleted.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Button("Undo") {
                Task { @MainActor in service.performUndo() }
            }
            .font(.subheadline.bold())
            .foregroundStyle(.orange)
            .accessibilityLabel("Undo delete \(entry.label)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}
