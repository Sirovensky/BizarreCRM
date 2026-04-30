import SwiftUI
import Core
import DesignSystem
import Networking

// §48.5 Recurring Import Schedule
//
// Allows admins to schedule automatic daily CSV imports from S3, Dropbox, or iCloud Drive.
// Also supports on-change webhook configuration (server calls a webhook URL → triggers import).
//
// Endpoint stubs (server routes not yet implemented):
//   GET  /imports/recurring           — list active schedules
//   POST /imports/recurring           — create a schedule
//   PUT  /imports/recurring/:id       — update
//   DELETE /imports/recurring/:id     — delete
//   POST /imports/recurring/:id/run-now — manual trigger
//   GET  /imports/webhooks/:id        — get webhook config
//   POST /imports/webhooks            — register webhook

// MARK: - Models

public enum RecurringImportSourceType: String, Codable, Sendable, CaseIterable, Identifiable {
    case s3       = "s3"
    case dropbox  = "dropbox"
    case icloud   = "icloud"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .s3:      return "Amazon S3"
        case .dropbox: return "Dropbox"
        case .icloud:  return "iCloud Drive"
        }
    }

    public var systemImage: String {
        switch self {
        case .s3:      return "server.rack"
        case .dropbox: return "arrow.triangle.2.circlepath.doc.fill"
        case .icloud:  return "icloud"
        }
    }

    /// Whether this source requires API credentials.
    public var requiresCredentials: Bool {
        switch self {
        case .s3, .dropbox: return true
        case .icloud:       return false
        }
    }
}

public enum RecurringImportFrequency: String, Codable, Sendable, CaseIterable, Identifiable {
    case hourly  = "hourly"
    case daily   = "daily"
    case weekly  = "weekly"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hourly:  return "Every hour"
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        }
    }
}

public struct RecurringImportSchedule: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var sourceType: RecurringImportSourceType
    public var entityType: ImportEntityType
    public var frequency: RecurringImportFrequency
    /// Local hour (0–23) to run the import.
    public var runAtHour: Int
    /// File path or URL on the remote source.
    public var filePath: String
    public var isActive: Bool
    public var lastRunAt: Date?
    public var lastRunStatus: String?
    public var nextRunAt: Date?

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        sourceType: RecurringImportSourceType = .icloud,
        entityType: ImportEntityType = .customers,
        frequency: RecurringImportFrequency = .daily,
        runAtHour: Int = 2,
        filePath: String = "",
        isActive: Bool = true,
        lastRunAt: Date? = nil,
        lastRunStatus: String? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceType = sourceType
        self.entityType = entityType
        self.frequency = frequency
        self.runAtHour = runAtHour
        self.filePath = filePath
        self.isActive = isActive
        self.lastRunAt = lastRunAt
        self.lastRunStatus = lastRunStatus
        self.nextRunAt = nextRunAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, frequency, isActive, filePath
        case sourceType   = "source_type"
        case entityType   = "entity_type"
        case runAtHour    = "run_at_hour"
        case lastRunAt    = "last_run_at"
        case lastRunStatus = "last_run_status"
        case nextRunAt    = "next_run_at"
    }
}

public struct ImportWebhook: Codable, Sendable, Identifiable {
    public let id: String
    /// The URL the server exposes for third-parties to POST to.
    public let inboundURL: String
    public var entityType: ImportEntityType
    public var isActive: Bool

    public init(id: String = UUID().uuidString,
                inboundURL: String = "",
                entityType: ImportEntityType = .customers,
                isActive: Bool = true) {
        self.id = id
        self.inboundURL = inboundURL
        self.entityType = entityType
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id
        case inboundURL   = "inbound_url"
        case entityType   = "entity_type"
        case isActive     = "is_active"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class RecurringImportViewModel {

    public private(set) var schedules: [RecurringImportSchedule] = []
    public private(set) var webhooks: [ImportWebhook] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    // Editor state
    public var showEditor = false
    public var editingSchedule: RecurringImportSchedule? = nil
    public var showWebhookEditor = false

    // Run-now state
    public private(set) var runningScheduleId: String? = nil

    @ObservationIgnored private let repository: RecurringImportRepository

    public init(repository: RecurringImportRepository) {
        self.repository = repository
    }

    // MARK: - Load

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        // §48.5 STUB NOTE: Server endpoints for recurring imports not yet implemented.
        // These calls will return 404 until /imports/recurring is added server-side.
        do {
            async let scheds = repository.listSchedules()
            async let hooks  = repository.listWebhooks()
            (schedules, webhooks) = try await (scheds, hooks)
        } catch {
            // Graceful degradation — show empty state when server endpoints not yet live.
            schedules = []
            webhooks = []
            AppLog.ui.info("Recurring imports: server stubs not yet available: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Save schedule

    public func saveSchedule(_ schedule: RecurringImportSchedule) async {
        isLoading = true
        defer { isLoading = false }
        do {
            if schedules.contains(where: { $0.id == schedule.id }) {
                let updated = try await repository.updateSchedule(schedule)
                schedules = schedules.map { $0.id == updated.id ? updated : $0 }
            } else {
                let created = try await repository.createSchedule(schedule)
                schedules.append(created)
            }
            showEditor = false
            editingSchedule = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete schedule

    public func deleteSchedule(id: String) async {
        do {
            try await repository.deleteSchedule(id: id)
            schedules.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Toggle active

    public func toggleActive(id: String) async {
        guard let idx = schedules.firstIndex(where: { $0.id == id }) else { return }
        var updated = schedules[idx]
        updated.isActive.toggle()
        await saveSchedule(updated)
    }

    // MARK: - Run now

    public func runNow(id: String) async {
        runningScheduleId = id
        defer { runningScheduleId = nil }
        do {
            _ = try await repository.runNow(id: id)
            await load()
        } catch {
            errorMessage = "Run failed: \(error.localizedDescription)"
        }
    }

    // MARK: - New / edit

    public func startNewSchedule() {
        editingSchedule = RecurringImportSchedule()
        showEditor = true
    }

    public func startEditing(_ s: RecurringImportSchedule) {
        editingSchedule = s
        showEditor = true
    }

    public func clearError() { errorMessage = nil }
}

// MARK: - RecurringImportView

public struct RecurringImportView: View {
    @State private var vm: RecurringImportViewModel

    public init(repository: RecurringImportRepository) {
        _vm = State(wrappedValue: RecurringImportViewModel(repository: repository))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .navigationTitle("Recurring Imports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.startNewSchedule()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add recurring import schedule")
            }
        }
        .sheet(isPresented: $vm.showEditor) {
            if let s = vm.editingSchedule {
                RecurringImportEditorSheet(
                    schedule: s,
                    onSave: { edited in Task { await vm.saveSchedule(edited) } },
                    onCancel: { vm.showEditor = false; vm.editingSchedule = nil }
                )
            }
        }
        .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.clearError() } })) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        List {
            schedulesSection
            webhooksSection
        }
        .listStyle(.insetGrouped)
    }

    private var regularLayout: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: BrandSpacing.base)],
                      spacing: BrandSpacing.base) {
                schedulesSection
                webhooksSection
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Schedules section

    @ViewBuilder
    private var schedulesSection: some View {
        Section {
            if vm.isLoading && vm.schedules.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if vm.schedules.isEmpty {
                emptySchedulesState
            } else {
                ForEach(vm.schedules) { schedule in
                    scheduleRow(schedule)
                }
            }
        } header: {
            Text("Scheduled Imports")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
        }
    }

    private var emptySchedulesState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No scheduled imports yet.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Add Schedule") { vm.startNewSchedule() }
                .buttonStyle(.plain)
                .foregroundStyle(.bizarreOrange)
                .font(.brandBodyMedium())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.md)
        .accessibilityLabel("No scheduled imports. Tap Add Schedule to create one.")
    }

    private func scheduleRow(_ s: RecurringImportSchedule) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: s.sourceType.systemImage)
                .foregroundStyle(.bizarreOrange)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(s.name.isEmpty ? "\(s.sourceType.displayName) → \(s.entityType.displayName)" : s.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.xs) {
                    Text(s.frequency.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if let last = s.lastRunAt {
                        Text("· Last: \(last.formatted(.relative(presentation: .named)))")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                if let status = s.lastRunStatus, !status.isEmpty {
                    statusBadge(status)
                }
            }
            Spacer()
            Toggle("", isOn: .constant(s.isActive))
                .labelsHidden()
                .tint(.bizarreSuccess)
                .onChange(of: s.isActive) { _, _ in
                    Task { await vm.toggleActive(id: s.id) }
                }
                .accessibilityLabel(s.isActive ? "Schedule active" : "Schedule paused")
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { vm.startEditing(s) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await vm.deleteSchedule(id: s.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                Task { await vm.runNow(id: s.id) }
            } label: {
                if vm.runningScheduleId == s.id {
                    ProgressView().tint(.white)
                } else {
                    Label("Run Now", systemImage: "play.circle")
                }
            }
            .tint(.bizarreOrange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.name.isEmpty ? s.sourceType.displayName : s.name), \(s.frequency.displayName), \(s.isActive ? "active" : "paused")")
        .hoverEffect(.highlight)
    }

    private func statusBadge(_ status: String) -> some View {
        let isSuccess = status == "completed" || status == "success"
        return Text(status.capitalized)
            .font(.brandLabelSmall())
            .foregroundStyle(isSuccess ? .bizarreSuccess : .bizarreError)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, 2)
            .background(
                (isSuccess ? Color.bizarreSuccess : Color.bizarreError).opacity(0.12),
                in: Capsule()
            )
    }

    // MARK: - Webhooks section

    @ViewBuilder
    private var webhooksSection: some View {
        Section {
            if vm.webhooks.isEmpty {
                emptyWebhooksState
            } else {
                ForEach(vm.webhooks) { hook in
                    webhookRow(hook)
                }
            }
        } header: {
            HStack {
                Text("On-Change Webhooks")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Button {
                    vm.showWebhookEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add webhook")
            }
        } footer: {
            Text("Webhooks let external systems trigger an import automatically when a file changes.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var emptyWebhooksState: some View {
        Text("No webhooks configured.")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("No webhooks configured")
    }

    private func webhookRow(_ hook: ImportWebhook) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(hook.entityType.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if hook.isActive {
                    Text("Active")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreSuccess)
                }
            }
            if !hook.inboundURL.isEmpty {
                Text(hook.inboundURL)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Webhook for \(hook.entityType.displayName), \(hook.isActive ? "active" : "inactive")")
    }
}

// MARK: - RecurringImportEditorSheet

private struct RecurringImportEditorSheet: View {
    @State private var draft: RecurringImportSchedule
    let onSave: (RecurringImportSchedule) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(schedule: RecurringImportSchedule,
         onSave: @escaping (RecurringImportSchedule) -> Void,
         onCancel: @escaping () -> Void) {
        _draft = State(wrappedValue: schedule)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isValid: Bool {
        !draft.filePath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Name") {
                        TextField("e.g. Daily customers sync", text: $draft.name)
                            .accessibilityLabel("Schedule name")
                    }

                    Section("Source") {
                        Picker("Source", selection: $draft.sourceType) {
                            ForEach(RecurringImportSourceType.allCases) { src in
                                Label(src.displayName, systemImage: src.systemImage).tag(src)
                            }
                        }
                        .accessibilityLabel("Import source")

                        TextField(filePathPrompt, text: $draft.filePath)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .accessibilityLabel("File path or URL")

                        if draft.sourceType.requiresCredentials {
                            Text("API credentials for \(draft.sourceType.displayName) are managed in Settings → Integrations.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }

                    Section("Entity") {
                        Picker("Import into", selection: $draft.entityType) {
                            ForEach(ImportEntityType.allCases) { e in
                                Label(e.displayName, systemImage: e.systemImage).tag(e)
                            }
                        }
                        .accessibilityLabel("Target entity type")
                    }

                    Section("Schedule") {
                        Picker("Frequency", selection: $draft.frequency) {
                            ForEach(RecurringImportFrequency.allCases) { f in
                                Text(f.displayName).tag(f)
                            }
                        }
                        .accessibilityLabel("Import frequency")

                        if draft.frequency != .hourly {
                            Stepper("Run at \(draft.runAtHour):00",
                                    value: $draft.runAtHour,
                                    in: 0...23)
                            .accessibilityLabel("Run at hour \(draft.runAtHour)")
                        }
                    }

                    Section {
                        Toggle("Active", isOn: $draft.isActive)
                            .tint(.bizarreSuccess)
                            .accessibilityLabel("Schedule is \(draft.isActive ? "active" : "paused")")
                    }
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(.bizarreOrange)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .disabled(!isValid)
                    .foregroundStyle(isValid ? .bizarreOrange : .bizarreOnSurfaceMuted)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var filePathPrompt: String {
        switch draft.sourceType {
        case .s3:      return "s3://bucket/path/to/file.csv"
        case .dropbox: return "/Dropbox/imports/file.csv"
        case .icloud:  return "file.csv (pick from Files)"
        }
    }
}
