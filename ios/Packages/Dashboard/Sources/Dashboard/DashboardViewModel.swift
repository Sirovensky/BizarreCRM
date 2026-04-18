import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class DashboardViewModel {
    public enum State: Sendable {
        case loading
        case loaded(DashboardSnapshot)
        case failed(String)
    }

    public var state: State = .loading

    @ObservationIgnored private let repo: DashboardRepository

    public init(repo: DashboardRepository) {
        self.repo = repo
    }

    public func load() async {
        if case .loaded = state {
            // Keep current data visible while re-fetching (soft refresh).
        } else {
            state = .loading
        }

        do {
            let snapshot = try await repo.load()
            state = .loaded(snapshot)
        } catch {
            AppLog.ui.error("Dashboard load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}
