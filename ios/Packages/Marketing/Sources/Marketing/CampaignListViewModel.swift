import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class CampaignListViewModel {
    public private(set) var campaigns: [Campaign] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var nextCursor: String?
    public private(set) var hasMore = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await api.listCampaigns(cursor: nil)
            campaigns = resp.campaigns
            nextCursor = resp.nextCursor
            hasMore = resp.nextCursor != nil
        } catch {
            AppLog.ui.error("Campaign list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadNextPage() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.listCampaigns(cursor: cursor)
            campaigns.append(contentsOf: resp.campaigns)
            nextCursor = resp.nextCursor
            hasMore = resp.nextCursor != nil
        } catch {
            AppLog.ui.error("Campaign next page failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
