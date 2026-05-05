import Foundation
import Observation
import Core

// MARK: - ConflictResolutionPhase

/// State-machine phases for conflict resolution.
public enum ConflictResolutionPhase: Sendable, Equatable {
    /// Fetching the conflict list from the server.
    case loading
    /// List is available; user is browsing or selecting a conflict.
    case idle
    /// User has opened a conflict and is deciding field-by-field.
    case resolving(conflictId: Int)
    /// The resolution was submitted successfully.
    case resolved(conflictId: Int, resolution: Resolution)
    /// An error occurred; message is user-displayable.
    case error(String)
}

// MARK: - ConflictResolutionViewModel

/// `@Observable` ViewModel driving `ConflictListView` and `ConflictDiffView`.
///
/// State machine:
///   `loading` → `idle` (list loaded)
///   `idle`    → `resolving(id)` (user taps a conflict)
///   `resolving(id)` → `resolved(id, res)` (POST /resolve succeeds)
///   any → `error(msg)` on network failure
@Observable
@MainActor
public final class ConflictResolutionViewModel {

    // MARK: - Published state

    /// Current phase of the state machine.
    public private(set) var phase: ConflictResolutionPhase = .loading

    /// Flat list loaded from the server.
    public private(set) var conflicts: [ConflictItem] = []

    /// Grouped by entity kind for sectioned display in `ConflictListView`.
    public var conflictsByEntityKind: [(key: String, items: [ConflictItem])] {
        let grouped = Dictionary(grouping: conflicts, by: \.entityKind)
        return grouped.sorted { $0.key < $1.key }.map { (key: $0.key, items: $0.value) }
    }

    /// Detail item currently open in `ConflictDiffView` (includes version JSON).
    public private(set) var selectedConflict: ConflictItem?

    /// Per-field "take this side" selection: field key → chosen side.
    public private(set) var fieldSelections: [String: ConflictSide] = [:]

    /// Notes for the resolution (user-editable in the diff view).
    public var resolutionNotes: String = ""

    /// Pagination cursor.
    public private(set) var currentPage: Int = 1
    public private(set) var totalPages: Int = 1
    public private(set) var isLoadingNextPage: Bool = false

    // MARK: - Active filter

    public var statusFilter: ConflictStatus? = .pending
    public var entityKindFilter: String? = nil

    // MARK: - Dependencies

    private let repository: ConflictResolutionRepositoryProtocol

    // MARK: - Init

    public init(repository: ConflictResolutionRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load / Refresh

    /// Fetch page 1 of conflicts. Resets existing list.
    public func loadConflicts() async {
        guard phase != .loading else { return }
        await setPhase(.loading)
        currentPage = 1
        await fetchPage(1, replacing: true)
    }

    /// Reload without clearing the existing list (pull-to-refresh).
    public func refresh() async {
        currentPage = 1
        await fetchPage(1, replacing: true)
    }

    /// Fetch the next page if available.
    public func loadNextPage() async {
        guard !isLoadingNextPage, currentPage < totalPages else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        let next = currentPage + 1
        await fetchPage(next, replacing: false)
    }

    // MARK: - Select conflict for diffing

    /// Load conflict detail (with version JSON) and transition to `.resolving`.
    public func selectConflict(_ item: ConflictItem) async {
        await setPhase(.resolving(conflictId: item.id))
        selectedConflict = nil
        fieldSelections = [:]
        resolutionNotes = ""
        do {
            let detail = try await repository.conflictDetail(id: item.id)
            selectedConflict = detail
            // Pre-populate field selections: default to server side.
            fieldSelections = Dictionary(
                uniqueKeysWithValues: detail.diffedFields.map { ($0.key, ConflictSide.server) }
            )
        } catch {
            await setPhase(.error(error.localizedDescription))
        }
    }

    /// Set the chosen side for a single field.
    public func selectSide(_ side: ConflictSide, for fieldKey: String) {
        fieldSelections[fieldKey] = side
    }

    // MARK: - Resolve

    /// Submit the resolution to `POST /api/v1/sync/conflicts/:id/resolve`.
    ///
    /// - Parameters:
    ///   - conflictId: The conflict to resolve.
    ///   - resolution: The chosen resolution strategy.
    public func submitResolution(conflictId: Int, resolution: Resolution) async {
        do {
            _ = try await repository.resolveConflict(
                id: conflictId,
                resolution: resolution,
                notes: resolutionNotes.isEmpty ? nil : resolutionNotes
            )
            // Remove the resolved item from the local list immediately (optimistic).
            conflicts.removeAll { $0.id == conflictId }
            selectedConflict = nil
            await setPhase(.resolved(conflictId: conflictId, resolution: resolution))
        } catch {
            await setPhase(.error(error.localizedDescription))
        }
    }

    /// Reset from `.resolved` or `.error` back to `.idle`.
    public func acknowledgeOutcome() async {
        await setPhase(.idle)
    }

    // MARK: - Private helpers

    private func fetchPage(_ page: Int, replacing: Bool) async {
        do {
            let envelope = try await repository.listConflicts(
                status: statusFilter,
                entityKind: entityKindFilter,
                page: page,
                pageSize: 25
            )
            if replacing {
                conflicts = envelope.rows
            } else {
                conflicts += envelope.rows
            }
            currentPage = envelope.page
            totalPages = envelope.pages
            await setPhase(.idle)
        } catch {
            await setPhase(.error(error.localizedDescription))
        }
    }

    private func setPhase(_ newPhase: ConflictResolutionPhase) async {
        phase = newPhase
    }
}
