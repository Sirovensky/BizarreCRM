import Foundation
import Observation
import Core
import Networking

// MARK: - PipelineStage

public enum PipelineStage: String, CaseIterable, Sendable, Hashable, Identifiable {
    case new        = "new"
    case qualified  = "qualified"
    case quoted     = "quoted"
    case won        = "won"
    case lost       = "lost"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .new:       return "New"
        case .qualified: return "Qualified"
        case .quoted:    return "Quoted"
        case .won:       return "Won"
        case .lost:      return "Lost"
        }
    }

    public var iconName: String {
        switch self {
        case .new:       return "star.fill"
        case .qualified: return "checkmark.seal.fill"
        case .quoted:    return "doc.text.fill"
        case .won:       return "trophy.fill"
        case .lost:      return "xmark.circle.fill"
        }
    }

    /// Maps a raw server status string (case-insensitive) to a pipeline stage.
    public static func from(status: String?) -> PipelineStage {
        guard let s = status?.lowercased() else { return .new }
        return PipelineStage(rawValue: s) ?? .new
    }
}

// MARK: - LeadPipelineViewModel

@MainActor
@Observable
public final class LeadPipelineViewModel {

    // MARK: State

    public enum State: Sendable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var state: State = .loading
    /// All leads, grouped by stage. Immutable map — use `moveCard` to update.
    public private(set) var grouped: [PipelineStage: [Lead]] = [:]
    /// Active filter: nil = all sources shown.
    public var sourceFilter: String? = nil

    // MARK: Private

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var allLeads: [Lead] = []

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        state = .loading
        do {
            allLeads = try await api.listLeads(pageSize: 200)
            applyFilter()
            state = .loaded
        } catch {
            AppLog.ui.error("Pipeline load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Filter

    public func setSourceFilter(_ source: String?) {
        sourceFilter = source
        applyFilter()
    }

    private func applyFilter() {
        let filtered: [Lead]
        if let sf = sourceFilter {
            filtered = allLeads.filter { $0.source?.lowercased() == sf.lowercased() }
        } else {
            filtered = allLeads
        }
        // Group by stage — immutable update.
        var newGrouped: [PipelineStage: [Lead]] = [:]
        for stage in PipelineStage.allCases {
            newGrouped[stage] = []
        }
        for lead in filtered {
            let stage = PipelineStage.from(status: lead.status)
            newGrouped[stage, default: []].append(lead)
        }
        grouped = newGrouped
    }

    // MARK: - Drag-drop

    /// Move a lead card from its current column to `destination`.
    /// Performs optimistic update first, then calls the API.
    public func moveCard(lead: Lead, to destination: PipelineStage) async {
        guard PipelineStage.from(status: lead.status) != destination else { return }

        // Optimistic: remove from old column, insert in new.
        var updated = grouped
        for stage in PipelineStage.allCases {
            updated[stage] = updated[stage]?.filter { $0.id != lead.id }
        }
        // Create updated lead with new status (immutable).
        let updatedLead = lead.withStatus(destination.rawValue)
        updated[destination, default: []].insert(updatedLead, at: 0)
        grouped = updated

        // Persist to allLeads as well.
        allLeads = allLeads.map { $0.id == lead.id ? updatedLead : $0 }

        // Network call.
        do {
            let body = LeadStatusUpdateBody(status: destination.rawValue)
            _ = try await api.updateLeadStatus(id: lead.id, body: body)
        } catch {
            AppLog.ui.error("Pipeline move failed: \(error.localizedDescription, privacy: .public)")
            // Rollback.
            await load()
        }
    }

    // MARK: - §9.2 Bulk archive won/lost

    /// Bulk-archive all leads in the `.won` or `.lost` stage.
    /// Optimistically clears the column, then patches each lead to `status=archived`.
    /// On error, reloads to restore correct state.
    public func bulkArchive(stage: PipelineStage) async {
        guard stage == .won || stage == .lost else { return }
        let targets = leads(in: stage)
        guard !targets.isEmpty else { return }

        // Optimistic: clear the column.
        var updated = grouped
        updated[stage] = []
        grouped = updated
        allLeads = allLeads.filter { lead in
            !targets.contains(where: { $0.id == lead.id })
        }

        // Persist: patch each lead to archived status.
        await withTaskGroup(of: Void.self) { group in
            for lead in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let body = LeadStatusUpdateBody(status: "archived")
                        _ = try await self.api.updateLeadStatus(id: lead.id, body: body)
                    } catch {
                        AppLog.ui.error(
                            "Bulk archive lead \(lead.id) failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        }

        // Reload to reconcile server state.
        await load()
    }

    // MARK: - Helpers

    public func leads(in stage: PipelineStage) -> [Lead] {
        grouped[stage] ?? []
    }

    public func totalValueCents(in stage: PipelineStage) -> Int {
        // Leads don't carry value in current model; return 0 until extended.
        _ = grouped[stage]
        return 0
    }
}
