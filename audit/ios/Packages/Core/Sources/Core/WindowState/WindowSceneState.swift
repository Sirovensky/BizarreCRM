import Foundation

// §22.4 Multi-window / Stage Manager — per-window scene state snapshot

// MARK: - ActiveTab

/// Identifies which root tab was active in a scene window.
public enum ActiveTab: String, Codable, Sendable, CaseIterable {
    case dashboard
    case tickets
    case customers
    case pos
    case reports
    case settings
}

// MARK: - WindowSceneState

/// A Codable snapshot of the UI state for one `UISceneSession`.
///
/// Captured when a window closes and rehydrated on next launch so the
/// user lands back on the same screen they left.
///
/// All fields are value types; the struct is immutable — produce updated
/// copies via the `with(...)` helpers rather than mutating in place.
public struct WindowSceneState: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// The root-level tab that was active.
    public let activeTab: ActiveTab

    /// ID of the ticket that was open in the detail pane, if any.
    public let selectedTicketId: String?

    /// ID of the customer that was open in the detail pane, if any.
    public let selectedCustomerId: String?

    /// Live search query string that was typed in the search field, if any.
    public let searchQuery: String?

    // MARK: - Init

    public init(
        activeTab: ActiveTab = .dashboard,
        selectedTicketId: String? = nil,
        selectedCustomerId: String? = nil,
        searchQuery: String? = nil
    ) {
        self.activeTab = activeTab
        self.selectedTicketId = selectedTicketId
        self.selectedCustomerId = selectedCustomerId
        self.searchQuery = searchQuery
    }

    // MARK: - Non-mutating updaters

    /// Returns a new state with `activeTab` replaced.
    public func withActiveTab(_ tab: ActiveTab) -> WindowSceneState {
        WindowSceneState(
            activeTab: tab,
            selectedTicketId: selectedTicketId,
            selectedCustomerId: selectedCustomerId,
            searchQuery: searchQuery
        )
    }

    /// Returns a new state with `selectedTicketId` replaced.
    public func withSelectedTicketId(_ id: String?) -> WindowSceneState {
        WindowSceneState(
            activeTab: activeTab,
            selectedTicketId: id,
            selectedCustomerId: selectedCustomerId,
            searchQuery: searchQuery
        )
    }

    /// Returns a new state with `selectedCustomerId` replaced.
    public func withSelectedCustomerId(_ id: String?) -> WindowSceneState {
        WindowSceneState(
            activeTab: activeTab,
            selectedTicketId: selectedTicketId,
            selectedCustomerId: id,
            searchQuery: searchQuery
        )
    }

    /// Returns a new state with `searchQuery` replaced.
    public func withSearchQuery(_ query: String?) -> WindowSceneState {
        WindowSceneState(
            activeTab: activeTab,
            selectedTicketId: selectedTicketId,
            selectedCustomerId: selectedCustomerId,
            searchQuery: query
        )
    }
}
