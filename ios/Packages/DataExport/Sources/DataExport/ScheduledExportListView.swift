import SwiftUI
import DesignSystem
import Core

// MARK: - ScheduledExportListView

/// Admin Settings → Data → Scheduled Exports list.
/// iPhone: NavigationStack. iPad: works as a detail panel.
public struct ScheduledExportListView: View {

    @State private var viewModel: DataExportViewModel
    @State private var showEditor: Bool = false
    @State private var editingSchedule: ScheduledExport?

    public init(viewModel: DataExportViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .task { await viewModel.loadSchedules() }
        .sheet(isPresented: $showEditor) {
            ScheduledExportEditorView(viewModel: viewModel, schedule: editingSchedule) {
                showEditor = false
                editingSchedule = nil
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            scheduleList
                .navigationTitle("Scheduled Exports")
                .exportInlineTitleMode()
                .toolbar { addButton }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        scheduleList
            .navigationTitle("Scheduled Exports")
            .toolbar { addButton }
    }

    // MARK: - Shared list

    @ViewBuilder
    private var scheduleList: some View {
        if viewModel.isLoadingSchedules {
            ProgressView("Loading schedules…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading scheduled exports")
        } else if viewModel.schedules.isEmpty {
            emptyState
        } else {
            List {
                ForEach(viewModel.schedules) { schedule in
                    scheduleRow(schedule)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteSchedule(id: schedule.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { indices in
                    let ids = indices.map { viewModel.schedules[$0].id }
                    Task {
                        for id in ids { await viewModel.deleteSchedule(id: id) }
                    }
                }
            }
        }
    }

    private func scheduleRow(_ schedule: ScheduledExport) -> some View {
        HStack {
            Image(systemName: schedule.destination.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(schedule.cadence.displayName) → \(schedule.destination.displayName)")
                    .font(.body)
                if let next = schedule.nextRunAt {
                    Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let last = schedule.lastRunAt {
                    Text("Last: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !schedule.destination.isImplemented {
                Text("Stub")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Not yet implemented")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(schedule.cadence.displayName) export to \(schedule.destination.displayName)")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Scheduled Exports")
                .font(.headline)
            Text("Add a schedule to automatically export your data on a recurring basis.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Add Schedule") { showEditor = true }
                .buttonStyle(.brandGlassProminent)
                .tint(Color.accentColor)
                .padding(.top, 8)
                .accessibilityLabel("Add Schedule")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                editingSchedule = nil
                showEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Add scheduled export")
        }
    }
}
