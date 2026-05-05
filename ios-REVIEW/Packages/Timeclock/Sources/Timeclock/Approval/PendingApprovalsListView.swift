import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §14 PendingApprovalsListView
//
// Manager iPad-primary view: groups pending clock entries per employee.
// iPad: NavigationSplitView sidebar (employee list) + detail (entry list for employee).
// iPhone: NavigationStack + collapsed List.
//
// Liquid Glass on toolbar chrome per visual language mandate.
// Bulk-approve button per employee row.
// Tap entry → RejectReasonSheet (sliding up from bottom / popover on iPad).

public struct PendingApprovalsListView: View {

    @Bindable var vm: PendingApprovalsViewModel
    @State private var selectedGroup: EmployeeGroup?
    @State private var entryForReject: ClockEntry?
    @State private var rejectReason: String = ""

    public init(vm: PendingApprovalsViewModel) {
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
        .navigationTitle("Pending Approvals")
        .toolbar { approvalToolbar }
        .task { await vm.load() }
        .sheet(item: $entryForReject) { entry in
            RejectReasonSheet(entry: entry, vm: vm) {
                entryForReject = nil
                rejectReason = ""
            }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            employeeList
                .navigationTitle("Employees")
                .frame(minWidth: 280, idealWidth: 340)
        } detail: {
            if let group = selectedGroup {
                EntryDetailPane(group: group, vm: vm, onReject: { entry in
                    entryForReject = entry
                })
            } else {
                ContentUnavailableView(
                    "Select an Employee",
                    systemImage: "person.2",
                    description: Text("Choose an employee to review their clock entries")
                )
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            ForEach(vm.groups) { group in
                NavigationLink(destination: EntryDetailPane(
                    group: group,
                    vm: vm,
                    onReject: { entry in entryForReject = entry }
                )) {
                    EmployeeGroupRow(group: group)
                }
            }
        }
        .overlay { stateOverlay }
        .refreshable { await vm.load() }
    }

    // MARK: - Employee list (iPad sidebar)

    private var employeeList: some View {
        List(selection: $selectedGroup) {
            ForEach(vm.groups) { group in
                EmployeeGroupRow(group: group)
                    .tag(group as EmployeeGroup?)
                    .brandHover()
            }
        }
        .overlay { stateOverlay }
        .refreshable { await vm.load() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var approvalToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Refresh") { Task { await vm.load() } }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh pending approvals")
        }
        ToolbarItem(placement: .status) {
            if vm.totalPendingCount > 0 {
                Text("\(vm.totalPendingCount) pending")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
                    .padding(.horizontal, BrandSpacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.bizarreOrange.opacity(0.12), in: Capsule())
                    .accessibilityLabel("\(vm.totalPendingCount) entries pending approval")
            }
        }
    }

    // MARK: - State overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading pending entries…")
                .accessibilityLabel("Loading pending approval entries")
        case let .failed(msg):
            ContentUnavailableView(
                "Failed to Load",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        case .loaded where vm.groups.isEmpty:
            ContentUnavailableView(
                "No Pending Entries",
                systemImage: "checkmark.circle",
                description: Text("All clock entries are up to date.")
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - EmployeeGroupRow

private struct EmployeeGroupRow: View {
    let group: EmployeeGroup

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(group.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(group.entries.count) entries")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            if group.pendingCount > 0 {
                Text("\(group.pendingCount)")
                    .font(.brandLabelSmall().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.bizarreOrange, in: Capsule())
                    .accessibilityLabel("\(group.pendingCount) pending")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("All approved")
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayName), \(group.pendingCount) pending")
    }
}

// MARK: - EntryDetailPane (iPad detail / iPhone destination)

struct EntryDetailPane: View {
    let group: EmployeeGroup
    let vm: PendingApprovalsViewModel
    let onReject: (ClockEntry) -> Void

    private static let isoFormatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        List {
            // Bulk approve button
            Section {
                BulkApproveButton(group: group, bulkState: vm.bulkState) {
                    Task { await vm.approveAll(employeeId: group.employeeId) }
                }
            }

            // Individual entries
            Section("Clock Entries") {
                ForEach(group.entries) { item in
                    EntryApprovalRow(
                        item: item,
                        onApprove: {
                            Task { await vm.approve(entry: item.entry) }
                        },
                        onReject: { onReject(item.entry) }
                    )
                    .brandHover()
                    .contextMenu {
                        Button("Approve") {
                            Task { await vm.approve(entry: item.entry) }
                        }
                        Button("Reject…", role: .destructive) {
                            onReject(item.entry)
                        }
                    }
                }
            }
        }
        .navigationTitle(group.displayName)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - BulkApproveButton

/// "Approve All" CTA for a single employee. §14 Task 3.
struct BulkApproveButton: View {
    let group: EmployeeGroup
    let bulkState: PendingApprovalsViewModel.BulkState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if bulkState == .processing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Processing bulk approval")
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text(bulkState == .done ? "All Approved" : "Approve All for \(group.displayName)")
                    .font(.brandBodyMedium())
            }
        }
        .disabled(group.allApproved || bulkState == .processing || bulkState == .done)
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .accessibilityLabel("Approve all pending entries for \(group.displayName)")
        .accessibilityIdentifier("approval.bulkApprove.\(group.employeeId)")
    }
}

// MARK: - EntryApprovalRow

private struct EntryApprovalRow: View {
    let item: ApprovalEntry
    let onApprove: () -> Void
    let onReject: () -> Void

    private static let isoFormatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(formattedDate(item.entry.clockIn))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.xs) {
                    Label(formattedTime(item.entry.clockIn), systemImage: "clock")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(item.entry.clockOut.map { formattedTime($0) } ?? "Active")
                        .font(.brandLabelSmall())
                        .foregroundStyle(item.entry.clockOut == nil ? .green : .bizarreOnSurfaceMuted)
                }
                if let hours = item.entry.totalHours {
                    Text(formatHours(hours))
                        .font(.brandLabelSmall().monospacedDigit())
                        .foregroundStyle(.bizarreOrange)
                }
            }
            Spacer()
            statusBadge
            actionButtons
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .pending:
            EmptyView()
        case .approved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Approved")
        case let .rejected(reason):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Rejected: \(reason)")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if item.status == .pending {
            HStack(spacing: BrandSpacing.xs) {
                Button {
                    onApprove()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Approve entry")
                .accessibilityIdentifier("approval.approve.\(item.entry.id)")

                Button {
                    onReject()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reject entry")
                .accessibilityIdentifier("approval.reject.\(item.entry.id)")
            }
        }
    }

    private var accessibilityLabel: String {
        let timeStr = "\(formattedTime(item.entry.clockIn)) to \(item.entry.clockOut.map { formattedTime($0) } ?? "active")"
        let hoursStr = item.entry.totalHours.map { ", \(formatHours($0))" } ?? ""
        let statusStr: String
        switch item.status {
        case .pending:   statusStr = ", pending approval"
        case .approved:  statusStr = ", approved"
        case let .rejected(reason): statusStr = ", rejected: \(reason)"
        }
        return "Clock entry \(formattedDate(item.entry.clockIn)), \(timeStr)\(hoursStr)\(statusStr)"
    }

    private func formattedDate(_ iso: String) -> String {
        guard let d = Self.isoFormatter.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func formattedTime(_ iso: String) -> String {
        guard let d = Self.isoFormatter.date(from: iso) else { return "?" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: d)
    }

    private func formatHours(_ h: Double) -> String {
        let hrs = Int(h)
        let min = Int((h - Double(hrs)) * 60)
        return min > 0 ? "\(hrs)h \(min)m" : "\(hrs)h"
    }
}

// MARK: - RejectReasonSheet

/// Bottom sheet on iPhone / popover on iPad for entering a rejection reason.
struct RejectReasonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: ClockEntry
    let vm: PendingApprovalsViewModel
    let onDismiss: () -> Void

    @State private var reason: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !reason.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    LabeledContent("Clock In", value: entry.clockIn)
                        .accessibilityLabel("Clock-in: \(entry.clockIn)")
                    if let out = entry.clockOut {
                        LabeledContent("Clock Out", value: out)
                            .accessibilityLabel("Clock-out: \(out)")
                    }
                }
                Section("Rejection Reason (required)") {
                    TextField("Enter reason for rejection", text: $reason, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityLabel("Rejection reason")
                        .accessibilityIdentifier("approval.rejectReason.\(entry.id)")
                }
                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(msg)")
                    }
                }
            }
            .navigationTitle("Reject Entry")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                    .accessibilityLabel("Cancel rejection")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reject") {
                        Task {
                            isSaving = true
                            await vm.reject(entry: entry, reason: reason)
                            isSaving = false
                            dismiss()
                            onDismiss()
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Confirm rejection")
                    .accessibilityIdentifier("approval.confirmReject.\(entry.id)")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - EmployeeGroup: Hashable conformance (needed for NavigationSplitView selection)

extension EmployeeGroup: Hashable {
    public static func == (lhs: EmployeeGroup, rhs: EmployeeGroup) -> Bool {
        lhs.employeeId == rhs.employeeId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(employeeId)
    }
}
