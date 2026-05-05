import Foundation
import Observation
import Core
import Networking

// §4 — Assignee picker for ticket create/edit flows.
//
// Wired: View → AssigneePickerViewModel → APIClient.ticketAssigneeCandidates()
//        (GET /api/v1/employees)
//
// The VM keeps the full unfiltered list in memory and filters client-side
// so the picker is instant after the first load. Active employees only.

@MainActor
@Observable
public final class AssigneePickerViewModel {

    // MARK: - State

    public private(set) var employees: [Employee] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    /// Live search text — filters `filtered` but does NOT re-fetch.
    public var searchText: String = ""

    /// Active-only employees matching `searchText`.
    public var filtered: [Employee] {
        let active = employees.filter { $0.active }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return active }
        let lower = searchText.lowercased()
        return active.filter {
            $0.displayName.lowercased().contains(lower) ||
            ($0.email?.lowercased().contains(lower) == true)
        }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            employees = try await api.ticketAssigneeCandidates()
        } catch {
            AppLog.ui.error(
                "AssigneePicker load failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }
}
