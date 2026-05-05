import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - TimesheetListView
//
// Displays clock entries from GET /api/v1/timesheet/clock-entries.
// Manager approval state is shown via manager-edit affordance (pencil icon).
// Edits call PATCH /api/v1/timesheet/clock-entries/:id.
//
// iPhone: NavigationStack + List.
// iPad: NavigationSplitView — list sidebar + detail pane.
// Edit sheet presented as a bottom sheet on iPhone, popover on iPad.

public struct TimesheetListView: View {

    @Bindable var vm: TimesheetListViewModel
    @State private var entryToEdit: ClockEntry?
    @State private var selectedEntry: ClockEntry?

    public init(vm: TimesheetListViewModel) {
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
        .navigationTitle("Timesheet")
        .task { await vm.load() }
        .sheet(item: $entryToEdit) { entry in
            ClockEntryEditSheet(entry: entry, vm: vm) {
                entryToEdit = nil
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            totalsSection
            entriesSection
        }
        .refreshable { await vm.load() }
        .overlay { stateOverlay }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedEntry) {
                totalsSection
                entriesSection
            }
            .navigationTitle("Timesheet")
            .frame(minWidth: 300, idealWidth: 380)
            .overlay { stateOverlay }
            .refreshable { await vm.load() }
        } detail: {
            if let entry = selectedEntry {
                ClockEntryDetailPanel(
                    entry: entry,
                    onEdit: { entryToEdit = entry }
                )
                .brandHover()
            } else {
                ContentUnavailableView(
                    "Select an Entry",
                    systemImage: "clock",
                    description: Text("Choose a clock entry from the list")
                )
            }
        }
    }

    // MARK: - Shared sections

    @ViewBuilder
    private var totalsSection: some View {
        if vm.loadState == .loaded {
            Section {
                HStack {
                    Text("Total Hours")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(formattedHours(vm.totalHours))
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total hours: \(formattedHours(vm.totalHours))")
            }
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        Section("Entries") {
            if vm.entries.isEmpty && vm.loadState == .loaded {
                Text("No clock entries found")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No clock entries found")
            } else {
                ForEach(vm.entries) { entry in
                    TimesheetEntryRow(entry: entry) {
                        entryToEdit = entry
                    }
                    .brandHover()
                }
            }
        }
    }

    // MARK: - State overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading timesheet…")
                .accessibilityLabel("Loading timesheet")
        case let .failed(msg):
            ContentUnavailableView(
                "Couldn't Load Timesheet",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func formattedHours(_ h: Double) -> String {
        let hrs = Int(h)
        let min = Int((h - Double(hrs)) * 60)
        return min > 0 ? "\(hrs)h \(min)m" : "\(hrs)h"
    }
}

// MARK: - TimesheetEntryRow

private struct TimesheetEntryRow: View {
    let entry: ClockEntry
    let onEdit: () -> Void

    private static let isoFormatter = ISO8601DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(spacing: BrandSpacing.xs) {
                    Label(dateLabel, systemImage: "calendar")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if entry.clockOut == nil {
                        Text("Active")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.green)
                            .padding(.horizontal, BrandSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                Text("\(clockInTime) → \(clockOutTime)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                if let hours = entry.totalHours {
                    Text(formattedHours(hours))
                        .font(.brandLabelSmall().monospacedDigit())
                        .foregroundStyle(.bizarreOrange)
                }
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit this clock entry")
                .accessibilityIdentifier("timesheet.editEntry.\(entry.id)")
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dateLabel: String {
        guard let date = Self.isoFormatter.date(from: entry.clockIn) else { return entry.clockIn }
        return Self.dateFormatter.string(from: date)
    }

    private var clockInTime: String {
        guard let date = Self.isoFormatter.date(from: entry.clockIn) else { return "?" }
        return Self.timeFormatter.string(from: date)
    }

    private var clockOutTime: String {
        guard let out = entry.clockOut, let date = Self.isoFormatter.date(from: out) else {
            return "Active"
        }
        return Self.timeFormatter.string(from: date)
    }

    private func formattedHours(_ h: Double) -> String {
        let hrs = Int(h)
        let min = Int((h - Double(hrs)) * 60)
        return min > 0 ? "\(hrs)h \(min)m" : "\(hrs)h"
    }

    private var accessibilityLabel: String {
        var label = "Shift on \(dateLabel), \(clockInTime) to \(clockOutTime)"
        if let h = entry.totalHours { label += ", \(formattedHours(h))" }
        return label
    }
}

// MARK: - ClockEntryEditSheet

/// Manager edit sheet — calls PATCH /api/v1/timesheet/clock-entries/:id.
/// `reason` is mandatory (server audit policy).
public struct ClockEntryEditSheet: View {

    @Environment(\.dismiss) private var dismiss

    let entry: ClockEntry
    let vm: TimesheetListViewModel
    let onDismiss: () -> Void

    @State private var clockInText: String
    @State private var clockOutText: String
    @State private var notesText: String
    @State private var reason: String = ""

    public init(entry: ClockEntry, vm: TimesheetListViewModel, onDismiss: @escaping () -> Void) {
        self.entry = entry
        self.vm = vm
        self.onDismiss = onDismiss
        _clockInText  = State(initialValue: entry.clockIn)
        _clockOutText = State(initialValue: entry.clockOut ?? "")
        _notesText    = State(initialValue: "")
    }

    private var canSave: Bool {
        !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Clock Times (ISO-8601 UTC)") {
                    LabeledContent("Clock In") {
                        TextField("Clock In", text: $clockInText)
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                            .accessibilityLabel("Clock-in timestamp")
                    }
                    LabeledContent("Clock Out") {
                        TextField("Clock Out (optional)", text: $clockOutText)
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                            .accessibilityLabel("Clock-out timestamp")
                    }
                }

                Section("Notes (optional)") {
                    TextField("Notes", text: $notesText, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                        .accessibilityLabel("Notes")
                }

                Section("Reason (required for audit log)") {
                    TextField("Correction reason", text: $reason, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityLabel("Correction reason")
                }

                if case let .failed(msg) = vm.editState {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(msg)")
                    }
                }
            }
            .navigationTitle("Edit Entry")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .accessibilityLabel("Cancel edit")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.editState == .saving {
                        ProgressView()
                            .accessibilityLabel("Saving changes")
                    } else {
                        Button("Save") {
                            Task {
                                await vm.editEntry(
                                    entryId: entry.id,
                                    clockIn: clockInText.isEmpty ? nil : clockInText,
                                    clockOut: clockOutText.isEmpty ? nil : clockOutText,
                                    notes: notesText.isEmpty ? nil : notesText,
                                    reason: reason
                                )
                                if case .saved = vm.editState { onDismiss() }
                            }
                        }
                        .disabled(!canSave)
                        .accessibilityLabel("Save shift correction")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - ClockEntryDetailPanel (iPad)

private struct ClockEntryDetailPanel: View {
    let entry: ClockEntry
    let onEdit: () -> Void

    private static let isoFormatter = ISO8601DateFormatter()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                statusCard
                timesSection
            }
            .padding(BrandSpacing.lg)
        }
        .navigationTitle("Clock Entry #\(entry.id)")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityLabel("Edit this clock entry")
                .accessibilityIdentifier("timesheet.detail.edit")
            }
        }
    }

    private var statusCard: some View {
        HStack {
            if entry.clockOut == nil {
                Label("Active shift", systemImage: "clock.fill")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.green)
            } else {
                Label("Completed", systemImage: "checkmark.circle")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Spacer()
            if let hours = entry.totalHours {
                Text(formattedHours(hours))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var timesSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            detailRow(label: "Clock In", value: formatted(entry.clockIn))
            detailRow(label: "Clock Out", value: entry.clockOut.map(formatted) ?? "–")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func formatted(_ iso: String) -> String {
        guard let date = Self.isoFormatter.date(from: iso) else { return iso }
        return Self.dateTimeFormatter.string(from: date)
    }

    private func formattedHours(_ h: Double) -> String {
        let hrs = Int(h)
        let min = Int((h - Double(hrs)) * 60)
        return min > 0 ? "\(hrs)h \(min)m" : "\(hrs)h"
    }
}
