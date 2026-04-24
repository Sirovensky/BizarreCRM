import SwiftUI
import Core
import DesignSystem

// MARK: - DataExportThreeColumnView

/// iPad-only 3-column layout for Data Export:
///   Column 1 (sidebar): `ExportKindSidebar` — On-Demand / Scheduled / GDPR / Settings
///   Column 2 (content): Job list or schedule list filtered by kind
///   Column 3 (detail):  `ExportDetailInspector` or `ScheduledExportDetailInspector`
///
/// Gate: only used when `!Platform.isCompact`. The calling site is responsible
/// for branching; this view assumes iPad/Mac and renders unconditionally.
public struct DataExportThreeColumnView: View {

    @State private var viewModel: DataExportViewModel
    @State private var selectedKind: ExportKind? = .onDemand
    @State private var selectedJobId: Int? = nil
    @State private var selectedScheduleId: Int? = nil
    @State private var showNewExportSheet: Bool = false
    @State private var shareURL: URL? = nil
    @State private var showShareSheet: Bool = false

    public init(viewModel: DataExportViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationSplitView {
            ExportKindSidebar(selection: $selectedKind)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .dataExportKeyboardShortcuts(
            onNewExport: { showNewExportSheet = true },
            onDownload: handleDownload,
            onShare: handleShare,
            onRefresh: handleRefresh,
            onCancelSelected: handleCancelSelected,
            onJumpKind: { selectedKind = $0 }
        )
        .sheet(isPresented: $showNewExportSheet) {
            ExportWizardSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ExportShareSheet(downloadURL: url)
            }
        }
        .task {
            await viewModel.loadSchedules()
        }
        .alert(
            "Export Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch selectedKind {
        case .onDemand:
            onDemandList
        case .scheduled:
            scheduledList
        case .gdpr:
            gdprPlaceholder
        case .settings:
            settingsPlaceholder
        case .none:
            ContentUnavailableView(
                "Select a Category",
                systemImage: "square.3.layers.3d",
                description: Text("Choose an export kind from the sidebar.")
            )
        }
    }

    // MARK: On-Demand list

    private var onDemandList: some View {
        Group {
            if let job = viewModel.startedJob {
                List(selection: $selectedJobId) {
                    onDemandRow(job: TenantExportJob(
                        id: Int(job.id) ?? 0,
                        status: job.status,
                        startedAt: nil,
                        completedAt: nil,
                        byteSize: nil,
                        errorMessage: job.errorMessage,
                        downloadUrl: job.downloadUrl
                    ))
                    .tag(Int(job.id) ?? 0)
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView {
                    Label("No Exports Yet", systemImage: "arrow.down.circle")
                } description: {
                    Text("Use ⌘N to start a new export.")
                } actions: {
                    Button("New Export") { showNewExportSheet = true }
                        .buttonStyle(.brandGlassProminent)
                        .tint(.accentColor)
                }
            }
        }
        .navigationTitle("On-Demand")
        .exportInlineTitleMode()
        .exportToolbarBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewExportSheet = true
                } label: {
                    Label("New Export", systemImage: "plus")
                }
                .keyboardShortcut(
                    DataExportKeyboardShortcuts.newExport.key,
                    modifiers: DataExportKeyboardShortcuts.newExport.modifiers
                )
                .accessibilityLabel("Start new export")
            }
        }
    }

    private func onDemandRow(job: TenantExportJob) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: job.status == .completed
                  ? "checkmark.circle.fill"
                  : job.status == .failed ? "xmark.circle.fill" : "arrow.2.circlepath")
                .foregroundStyle(job.status == .completed ? Color.green
                                 : job.status == .failed ? Color.red : Color.accentColor)
                .frame(width: DesignTokens.Spacing.xl)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Export #\(job.id)")
                    .font(.body.bold())
                Text(job.status.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !job.status.isTerminal {
                ProgressView(value: job.status.progress, total: 1.0)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .hoverEffect(.highlight)
        .exportContextMenu(
            job: job,
            isScheduled: false,
            actions: ExportContextMenuActions(
                onDownload: { handleDownload() },
                onCancel: { handleCancelSelected() },
                onViewDetails: { selectedJobId = job.id }
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Export \(job.id), \(job.status.displayLabel)")
    }

    // MARK: Scheduled list

    private var scheduledList: some View {
        Group {
            if viewModel.isLoadingSchedules {
                ProgressView("Loading schedules…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.schedules.isEmpty {
                ContentUnavailableView {
                    Label("No Schedules", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Create a recurring export schedule.")
                }
            } else {
                List(viewModel.schedules, selection: $selectedScheduleId) { schedule in
                    scheduledRow(schedule)
                        .tag(schedule.id)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Scheduled")
        .exportInlineTitleMode()
        .exportToolbarBackground()
        .refreshable {
            await viewModel.loadSchedules()
        }
    }

    private func scheduledRow(_ schedule: ExportSchedule) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: schedule.status.systemImage)
                .foregroundStyle(schedule.status == .active ? Color.green
                                 : schedule.status == .paused ? Color.orange : Color.secondary)
                .frame(width: DesignTokens.Spacing.xl)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(schedule.name)
                    .font(.body.bold())
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(schedule.exportType.displayName)
                    Text("·")
                    Text(schedule.intervalKind.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            BrandGlassBadge(schedule.status.displayName, variant: .regular)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .hoverEffect(.highlight)
        .contextMenu {
            Button {
                selectedScheduleId = schedule.id
            } label: {
                Label("View Details", systemImage: "info.circle")
            }

            Divider()

            if schedule.status == .active {
                Button {
                    Task { await viewModel.pauseSchedule(id: schedule.id) }
                } label: {
                    Label("Pause Schedule", systemImage: "pause.circle")
                }
            } else if schedule.status == .paused {
                Button {
                    Task { await viewModel.resumeSchedule(id: schedule.id) }
                } label: {
                    Label("Resume Schedule", systemImage: "play.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                Task { await viewModel.cancelSchedule(id: schedule.id) }
            } label: {
                Label("Cancel Schedule", systemImage: "xmark.circle")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(schedule.name), \(schedule.status.displayName)")
    }

    // MARK: GDPR placeholder (wired to existing GDPRCustomerExportView)

    private var gdprPlaceholder: some View {
        ContentUnavailableView(
            "GDPR Export",
            systemImage: "person.badge.shield.checkmark.fill",
            description: Text("Select a customer to export or erase their data.")
        )
        .navigationTitle("GDPR")
        .exportInlineTitleMode()
    }

    // MARK: Settings placeholder

    private var settingsPlaceholder: some View {
        ContentUnavailableView(
            "Settings Export",
            systemImage: "gearshape.2.fill",
            description: Text("Export or import app configuration settings.")
        )
        .navigationTitle("Settings")
        .exportInlineTitleMode()
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        switch selectedKind {
        case .scheduled:
            if let id = selectedScheduleId,
               let schedule = viewModel.schedules.first(where: { $0.id == id }) {
                ScheduledExportDetailInspector(
                    schedule: schedule,
                    recentRuns: [],
                    onPause: { Task { await viewModel.pauseSchedule(id: id) } },
                    onResume: { Task { await viewModel.resumeSchedule(id: id) } },
                    onCancel: { Task { await viewModel.cancelSchedule(id: id) } }
                )
            } else {
                detailPlaceholder(icon: "calendar.badge.clock", message: "Select a schedule to inspect.")
            }
        case .onDemand:
            if let job = viewModel.startedJob.flatMap({ j -> TenantExportJob? in
                guard let jid = Int(j.id), jid == selectedJobId else { return nil }
                return TenantExportJob(
                    id: jid, status: j.status,
                    errorMessage: j.errorMessage, downloadUrl: j.downloadUrl
                )
            }) {
                ExportDetailInspector(
                    job: job,
                    entity: viewModel.wizardEntity,
                    format: viewModel.wizardFormat,
                    onDownload: handleDownload,
                    onShare: { url in
                        shareURL = url
                        showShareSheet = true
                    }
                )
            } else {
                detailPlaceholder(icon: "arrow.down.circle", message: "Select an export to inspect.")
            }
        default:
            detailPlaceholder(icon: "square.3.layers.3d", message: "Select an item to see details.")
        }
    }

    private func detailPlaceholder(icon: String, message: String) -> some View {
        ContentUnavailableView {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        } description: {
            Text(message)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Keyboard action handlers

    private func handleDownload() {
        guard let urlString = viewModel.startedJob?.downloadUrl,
              let url = URL(string: urlString) else { return }
        shareURL = url
        showShareSheet = true
    }

    private func handleShare() {
        handleDownload()
    }

    private func handleRefresh() {
        Task {
            await viewModel.loadSchedules()
        }
    }

    private func handleCancelSelected() {
        if let id = selectedScheduleId {
            Task { await viewModel.cancelSchedule(id: id) }
        }
    }
}

// MARK: - ExportWizardSheet (thin adapter for the three-column)

/// Thin sheet wrapper so the new-export action can be triggered from the toolbar
/// and keyboard shortcut without coupling to a specific wizard entry point.
private struct ExportWizardSheet: View {
    let viewModel: DataExportViewModel

    var body: some View {
        NavigationStack {
            ExportWizardView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Wizard handles its own dismiss via @Environment(\.dismiss)
                        EmptyView()
                    }
                }
        }
    }
}
