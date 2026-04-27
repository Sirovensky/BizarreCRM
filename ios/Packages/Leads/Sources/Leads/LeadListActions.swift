import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.1 Lead list context menu, swipe actions, and bulk delete

// MARK: - Lead list swipe & context menu extensions

extension LeadListView {

    // MARK: - §9.1 Swipe — advance / drop stage

    @ViewBuilder
    func leadingSwipeActions(for lead: Lead, vm: LeadListViewModel) -> some View {
        if let status = lead.status, status != "converted", status != "won" {
            Button {
                Task { await vm.advanceStage(for: lead) }
            } label: {
                Label("Advance", systemImage: "arrow.right.circle.fill")
            }
            .tint(.bizarreOrange)
        }
    }

    @ViewBuilder
    func trailingSwipeActions(for lead: Lead, vm: LeadListViewModel) -> some View {
        Button(role: .destructive) {
            Task { await vm.deleteLead(lead) }
        } label: {
            Label("Delete", systemImage: "trash.fill")
        }

        Button {
            Task { await vm.dropStage(for: lead) }
        } label: {
            Label("Drop", systemImage: "arrow.down.circle.fill")
        }
        .tint(.bizarreError.opacity(0.7))
    }

    // MARK: - §9.1 Context menu

    @ViewBuilder
    func leadContextMenu(for lead: Lead, vm: LeadListViewModel, onOpen: @escaping () -> Void) -> some View {
        Button { onOpen() } label: {
            Label("Open", systemImage: "magnifyingglass")
        }
        .accessibilityLabel("Open lead \(lead.displayName)")

        if let phone = lead.phone, !phone.isEmpty {
            Button {
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:\(digits)") {
                    #if canImport(UIKit)
                    UIApplication.shared.open(url)
                    #endif
                }
            } label: {
                Label("Call", systemImage: "phone.fill")
            }
            .accessibilityLabel("Call \(lead.displayName)")

            Button {
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "sms:\(digits)") {
                    #if canImport(UIKit)
                    UIApplication.shared.open(url)
                    #endif
                }
            } label: {
                Label("SMS", systemImage: "message.fill")
            }
            .accessibilityLabel("SMS \(lead.displayName)")
        }

        if let email = lead.email, !email.isEmpty {
            Button {
                if let url = URL(string: "mailto:\(email)") {
                    #if canImport(UIKit)
                    UIApplication.shared.open(url)
                    #endif
                }
            } label: {
                Label("Email", systemImage: "envelope.fill")
            }
            .accessibilityLabel("Email \(lead.displayName)")
        }

        Divider()

        Button {
            Task { await vm.advanceStage(for: lead) }
        } label: {
            Label("Advance stage", systemImage: "arrow.right.circle")
        }
        .accessibilityLabel("Advance \(lead.displayName) to next stage")

        Divider()

        Button(role: .destructive) {
            Task { await vm.deleteLead(lead) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityLabel("Delete lead \(lead.displayName)")
    }
}

// MARK: - §9.1 Bulk delete with undo on LeadListViewModel

@MainActor
extension LeadListViewModel {

    // MARK: - Stage transitions

    /// Advance a lead to the next pipeline stage optimistically.
    public func advanceStage(for lead: Lead) async {
        guard let current = lead.status else { return }
        let next = Self.nextStage(after: current)
        guard let next else { return }
        await updateLeadStatus(lead: lead, newStatus: next)
    }

    /// Drop a lead stage one step back.
    public func dropStage(for lead: Lead) async {
        guard let current = lead.status else { return }
        let prev = Self.previousStage(before: current)
        guard let prev else { return }
        await updateLeadStatus(lead: lead, newStatus: prev)
    }

    private func updateLeadStatus(lead: Lead, newStatus: String) async {
        // Optimistic update
        if let idx = items.firstIndex(where: { $0.id == lead.id }) {
            items[idx] = items[idx].withStatus(newStatus)
        }
        // Server sync
        let req = LeadStatusUpdateBody(status: newStatus)
        do {
            _ = try await api.updateLeadStatus(id: lead.id, body: req)
        } catch {
            AppLog.ui.error("Lead stage update failed: \(error.localizedDescription, privacy: .public)")
            // Rollback on failure
            await load()
        }
    }

    // MARK: - §9.1 Bulk delete with undo

    /// Returns deleted leads for potential undo.
    @discardableResult
    public func bulkDelete(ids: Set<Int64>) async -> [Lead] {
        let toDelete = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        var failedIds: [Int64] = []
        await withTaskGroup(of: (Int64, Bool).self) { group in
            for id in ids {
                group.addTask {
                    do {
                        try await self.api.deleteLead(id: id)
                        return (id, true)
                    } catch {
                        AppLog.ui.error("Lead delete \(id) failed: \(error.localizedDescription, privacy: .public)")
                        return (id, false)
                    }
                }
            }
            for await (id, succeeded) in group {
                if !succeeded { failedIds.append(id) }
            }
        }
        if !failedIds.isEmpty {
            // Restore failed deletes
            let restored = toDelete.filter { failedIds.contains($0.id) }
            items.append(contentsOf: restored)
        }
        return toDelete.filter { !failedIds.contains($0.id) }
    }

    /// Undo: re-create deleted leads (re-fetch from server to restore).
    public func undoBulkDelete(leads: [Lead]) async {
        // Re-insert optimistically then reload to get server truth
        items.insert(contentsOf: leads, at: 0)
        await load()
    }

    // MARK: - Single delete

    public func deleteLead(_ lead: Lead) async {
        items.removeAll { $0.id == lead.id }
        do {
            try await api.deleteLead(id: lead.id)
        } catch {
            AppLog.ui.error("Lead delete failed: \(error.localizedDescription, privacy: .public)")
            await load()
        }
    }

    // MARK: - Stage order

    static let stageOrder: [String] = [
        "new", "contacted", "scheduled", "qualified", "proposal", "converted", "won", "lost"
    ]

    static func nextStage(after status: String) -> String? {
        let lower = status.lowercased()
        guard let idx = stageOrder.firstIndex(of: lower),
              idx + 1 < stageOrder.count else { return nil }
        // Don't auto-advance past "proposal" — terminal states need explicit action
        let next = stageOrder[idx + 1]
        guard next != "converted", next != "won", next != "lost" else { return nil }
        return next
    }

    static func previousStage(before status: String) -> String? {
        let lower = status.lowercased()
        guard let idx = stageOrder.firstIndex(of: lower), idx > 0 else { return nil }
        return stageOrder[idx - 1]
    }
}

// MARK: - APIClient extension for lead delete

extension APIClient {
    /// `DELETE /api/v1/leads/:id` — delete a lead (no response body expected).
    public func deleteLead(id: Int64) async throws {
        try await delete("/api/v1/leads/\(id)")
    }
}
