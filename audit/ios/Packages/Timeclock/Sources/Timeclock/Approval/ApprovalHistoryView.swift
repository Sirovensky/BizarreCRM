import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §14 ApprovalHistoryViewModel
//
// Loads clock_entry_edits for a given clock entry from the server.
// The server's PATCH /api/v1/timesheet/clock-entries/:id writes one row to
// clock_entry_edits per edit with editor_user_id, before/after JSON, reason,
// and edited_at.  No dedicated "history" endpoint exists; we surface the audit
// trail that is already present in the PATCH response chain, stored locally
// after each approval action.
//
// Since the server has no GET for clock_entry_edits yet, this view accepts
// history rows passed in directly (populated by PendingApprovalsViewModel
// which collects them from PATCH responses). This avoids inventing a route.

@MainActor
@Observable
public final class ApprovalHistoryViewModel {

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var historyEntries: [ApprovalHistoryEntry] = []

    public var clockEntryId: Int64?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Populates history from entries already known client-side (post-PATCH).
    public func populate(with entries: [ApprovalHistoryEntry]) {
        historyEntries = entries
            .filter { clockEntryId == nil || $0.clockEntryId == clockEntryId }
            .sorted { $0.editedAt > $1.editedAt }
        loadState = .loaded
    }

    /// Re-filter when clockEntryId changes.
    public func filterByCurrent(allHistory: [ApprovalHistoryEntry]) {
        populate(with: allHistory)
    }
}

// MARK: - ApprovalHistoryView

/// Shows who approved/rejected what and when.
/// iPad: Table with sortable columns. iPhone: List rows.
public struct ApprovalHistoryView: View {

    @Bindable var vm: ApprovalHistoryViewModel

    public init(vm: ApprovalHistoryViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Approval History")
        .overlay { stateOverlay }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            if vm.historyEntries.isEmpty && vm.loadState == .loaded {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No approval actions recorded yet.")
                )
            } else {
                ForEach(vm.historyEntries) { row in
                    HistoryRow(entry: row)
                }
            }
        }
    }

    // MARK: - iPad layout — Table with sortable columns

    private var iPadLayout: some View {
        Table(vm.historyEntries) {
            TableColumn("Entry ID") { row in
                Text("#\(row.clockEntryId)")
                    .font(.brandLabelSmall().monospacedDigit())
                    .textSelection(.enabled)
                    .accessibilityLabel("Clock entry \(row.clockEntryId)")
            }
            TableColumn("Editor") { row in
                Text("User #\(row.editorUserId)")
                    .font(.brandLabelSmall())
                    .textSelection(.enabled)
                    .accessibilityLabel("Editor user \(row.editorUserId)")
            }
            TableColumn("Action / Reason") { row in
                Text(row.reason)
                    .font(.brandLabelSmall())
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .foregroundStyle(reasonColor(row.reason))
                    .accessibilityLabel("Reason: \(row.reason)")
            }
            TableColumn("When") { row in
                Text(formattedDate(row.editedAt))
                    .font(.brandLabelSmall())
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .accessibilityLabel("At: \(formattedDate(row.editedAt))")
            }
        }
    }

    // MARK: - State overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading history…")
                .accessibilityLabel("Loading approval history")
        case let .failed(msg):
            ContentUnavailableView(
                "Failed to Load",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let d = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: d)
    }

    private func reasonColor(_ reason: String) -> Color {
        if reason.hasPrefix(ApprovalReasonPrefix.approved) { return .green }
        if reason.hasPrefix(ApprovalReasonPrefix.rejected) { return .red }
        return .bizarreOnSurface
    }
}

// MARK: - HistoryRow (iPhone list row)

private struct HistoryRow: View {
    let entry: ApprovalHistoryEntry

    private static let isoFormatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Text(actionLabel)
                    .font(.brandBodyMedium())
                    .foregroundStyle(actionColor)
                Spacer()
                Text(formattedDate)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            HStack(spacing: BrandSpacing.xs) {
                Text("Entry #\(entry.clockEntryId)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("·")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("By User #\(entry.editorUserId)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if !ApprovalReasonPrefix.isApprovalAction(entry.reason) || entry.reason.count > 12 {
                Text(entry.reason)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(actionLabel) on entry \(entry.clockEntryId) by user \(entry.editorUserId), \(formattedDate)")
        .brandHover()
    }

    private var actionLabel: String {
        if entry.reason.hasPrefix(ApprovalReasonPrefix.approved) { return "Approved" }
        if entry.reason.hasPrefix(ApprovalReasonPrefix.rejected) { return "Rejected" }
        return "Edited"
    }

    private var actionColor: Color {
        if entry.reason.hasPrefix(ApprovalReasonPrefix.approved) { return .green }
        if entry.reason.hasPrefix(ApprovalReasonPrefix.rejected) { return .red }
        return .bizarreOnSurface
    }

    private var formattedDate: String {
        guard let d = Self.isoFormatter.date(from: entry.editedAt) else { return entry.editedAt }
        return Self.displayFormatter.string(from: d)
    }
}
