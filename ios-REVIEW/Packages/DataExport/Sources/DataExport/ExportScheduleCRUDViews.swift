import SwiftUI
import DesignSystem
import Core

// MARK: - ExportScheduleListView
// Uses the server-accurate ExportSchedule model (id: Int, name, export_type, interval_kind, etc.)

public struct ExportScheduleListView: View {

    @State private var viewModel: DataExportViewModel
    @State private var showCreator: Bool = false
    @State private var editingSchedule: ExportSchedule? = nil

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
        .sheet(isPresented: $showCreator, onDismiss: { editingSchedule = nil }) {
            ExportScheduleEditorView(viewModel: viewModel, schedule: editingSchedule) {
                showCreator = false
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
                .navigationTitle("Export Schedules")
                .exportInlineTitleMode()
                .exportToolbarBackground()
                .toolbar { addButton }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        scheduleList
            .navigationTitle("Export Schedules")
            .exportToolbarBackground()
            .toolbar { addButton }
    }

    // MARK: - List

    @ViewBuilder
    private var scheduleList: some View {
        if viewModel.isLoadingSchedules {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading export schedules")
        } else if viewModel.schedules.isEmpty {
            emptyState
        } else {
            List {
                ForEach(viewModel.schedules) { schedule in
                    scheduleRow(schedule)
                        .hoverEffect(.highlight)
                        .contextMenu {
                            scheduleContextMenu(schedule)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.cancelSchedule(id: schedule.id) }
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if schedule.status == .active {
                                Button {
                                    Task { await viewModel.pauseSchedule(id: schedule.id) }
                                } label: {
                                    Label("Pause", systemImage: "pause.circle")
                                }
                                .tint(.orange)
                            } else if schedule.status == .paused {
                                Button {
                                    Task { await viewModel.resumeSchedule(id: schedule.id) }
                                } label: {
                                    Label("Resume", systemImage: "play.circle")
                                }
                                .tint(.green)
                            }
                        }
                }
            }
            .exportListStyle()
        }
    }

    private func scheduleRow(_ schedule: ExportSchedule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: schedule.exportType.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.name)
                    .font(.body)

                Text("\(schedule.exportType.displayName) · every \(schedule.intervalCount) \(schedule.intervalKind.displayName.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let next = schedule.nextRunAt {
                    Text("Next: \(next)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            scheduleStatusBadge(schedule.status)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(schedule.name), \(schedule.exportType.displayName), \(schedule.intervalKind.displayName), status \(schedule.status.displayName)")
    }

    private func scheduleStatusBadge(_ status: ScheduleStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.caption2)
            Text(status.displayName)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor(status).opacity(0.15), in: Capsule())
        .foregroundStyle(statusColor(status))
        .accessibilityHidden(true)
    }

    private func statusColor(_ status: ScheduleStatus) -> Color {
        switch status {
        case .active:   return .green
        case .paused:   return .orange
        case .canceled: return .red
        }
    }

    @ViewBuilder
    private func scheduleContextMenu(_ schedule: ExportSchedule) -> some View {
        Button {
            editingSchedule = schedule
            showCreator = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .accessibilityLabel("Edit \(schedule.name)")

        Divider()

        if schedule.status == .active {
            Button {
                Task { await viewModel.pauseSchedule(id: schedule.id) }
            } label: {
                Label("Pause", systemImage: "pause.circle")
            }
        } else if schedule.status == .paused {
            Button {
                Task { await viewModel.resumeSchedule(id: schedule.id) }
            } label: {
                Label("Resume", systemImage: "play.circle")
            }
        }

        Divider()

        Button(role: .destructive) {
            Task { await viewModel.cancelSchedule(id: schedule.id) }
        } label: {
            Label("Cancel Schedule", systemImage: "xmark.circle")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Export Schedules")
                .font(.headline)

            Text("Add a recurring schedule to automatically export your data.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Add Schedule") {
                editingSchedule = nil
                showCreator = true
            }
            .buttonStyle(.brandGlassProminent)
            .tint(Color.accentColor)
            .padding(.top, 8)
            .accessibilityLabel("Add export schedule")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                editingSchedule = nil
                showCreator = true
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Add export schedule")
        }
    }
}

// MARK: - ExportScheduleEditorView

/// Create or edit an ExportSchedule. Uses server model fields directly.
public struct ExportScheduleEditorView: View {

    @State private var viewModel: DataExportViewModel

    // Form state
    @State private var name: String
    @State private var exportType: ExportEntity
    @State private var intervalKind: ScheduleIntervalKind
    @State private var intervalCount: Int
    @State private var deliveryEmail: String
    @State private var isSaving: Bool = false

    private let existingSchedule: ExportSchedule?
    private let onDismiss: () -> Void

    public init(
        viewModel: DataExportViewModel,
        schedule: ExportSchedule? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self._viewModel = State(wrappedValue: viewModel)
        self.existingSchedule = schedule
        self.onDismiss = onDismiss

        // Pre-fill from existing schedule or defaults
        self._name          = State(wrappedValue: schedule?.name ?? "")
        self._exportType    = State(wrappedValue: schedule?.exportType ?? .full)
        self._intervalKind  = State(wrappedValue: schedule?.intervalKind ?? .daily)
        self._intervalCount = State(wrappedValue: schedule?.intervalCount ?? 1)
        self._deliveryEmail = State(wrappedValue: schedule?.deliveryEmail ?? "")
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
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
            editorForm
                .navigationTitle(existingSchedule == nil ? "New Schedule" : "Edit Schedule")
                .exportInlineTitleMode()
                .exportToolbarBackground()
                .toolbar { toolbarContent }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        editorForm
            .navigationTitle(existingSchedule == nil ? "New Schedule" : "Edit Schedule")
            .exportToolbarBackground()
            .toolbar { toolbarContent }
    }

    // MARK: - Form

    private var editorForm: some View {
        Form {
            Section("Schedule name") {
                TextField("E.g. Daily customer backup", text: $name)
                    .accessibilityLabel("Schedule name")
            }

            Section("What to export") {
                Picker("Entity", selection: $exportType) {
                    ForEach(ExportEntity.allCases, id: \.self) { e in
                        Label(e.displayName, systemImage: e.systemImage).tag(e)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("Export entity")
            }

            Section("Frequency") {
                Picker("Interval", selection: $intervalKind) {
                    ForEach(ScheduleIntervalKind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Export interval kind")

                Stepper("Every \(intervalCount) \(intervalKind.displayName.lowercased())",
                        value: $intervalCount, in: 1...31)
                    .accessibilityLabel("Interval count: \(intervalCount)")
            }

            Section {
                TextField("Optional", text: $deliveryEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .accessibilityLabel("Delivery email address")
            } header: {
                Text("Delivery email (optional)")
            } footer: {
                Text("Leave blank to store exports locally only.")
                    .font(.caption)
            }
        }
        .disabled(isSaving)
        .exportListStyle()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { onDismiss() }
                .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
                    .accessibilityLabel("Saving…")
            } else {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Save schedule")
            }
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let email: String? = deliveryEmail.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : deliveryEmail.trimmingCharacters(in: .whitespaces)

        if let existing = existingSchedule {
            let req = UpdateScheduleRequest(
                name: trimmedName,
                exportType: exportType,
                intervalKind: intervalKind,
                intervalCount: intervalCount,
                deliveryEmail: email
            )
            await viewModel.updateSchedule(id: existing.id, request: req)
        } else {
            let startDate = ISO8601DateFormatter().string(from: Date())
            let req = CreateScheduleRequest(
                name: trimmedName,
                exportType: exportType,
                intervalKind: intervalKind,
                intervalCount: intervalCount,
                startDate: startDate,
                deliveryEmail: email
            )
            await viewModel.createSchedule(req)
        }

        if viewModel.errorMessage == nil {
            onDismiss()
        }
    }
}
