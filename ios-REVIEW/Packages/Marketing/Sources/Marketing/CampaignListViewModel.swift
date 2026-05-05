import Foundation
import Observation
import Core
import Networking

public enum CampaignListFilter: String, CaseIterable, Sendable {
    case active, scheduled, past, all

    public var displayName: String {
        switch self {
        case .active:    return "Active"
        case .scheduled: return "Scheduled"
        case .past:      return "Past"
        case .all:       return "All"
        }
    }
}

@MainActor
@Observable
public final class CampaignListViewModel {
    public private(set) var allCampaigns: [Campaign] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    // Legacy pagination stubs (server returns all in one page)
    public private(set) var nextCursor: String? = nil
    public private(set) var hasMore: Bool = false
    public var filter: CampaignListFilter = .all

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: Derived

    public var campaigns: [Campaign] {
        switch filter {
        case .all:
            return allCampaigns
        case .active:
            return allCampaigns.filter { CampaignStatus.activeCases.contains($0.status) }
        case .scheduled:
            return allCampaigns.filter { CampaignStatus.scheduledCases.contains($0.status) }
        case .past:
            return allCampaigns.filter { CampaignStatus.pastCases.contains($0.status) }
        }
    }

    // MARK: Load

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows = try await api.listCampaignsServer()
            allCampaigns = rows.map { Campaign.from($0) }
        } catch {
            AppLog.ui.error("Campaign list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// No-op on real server (returns all in one page), kept for compat.
    public func loadNextPage() async {
        // Server returns all campaigns in one call — nothing to page.
    }

    public func delete(id: Int) async {
        do {
            try await api.deleteCampaignServer(id: id)
            allCampaigns.removeAll { $0.serverRowId == id }
        } catch {
            AppLog.ui.error("Campaign delete failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
