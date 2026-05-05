import SwiftUI
import DesignSystem
import Core

// MARK: - ExportWizardView

/// §49.2 Export wizard: entity selection, format, date range, trigger.
/// iPhone: NavigationStack wizard with step-by-step flow.
/// iPad: Inspector / side panel with all steps visible at once.
public struct ExportWizardView: View {

    @State private var viewModel: DataExportViewModel
    @State private var progressViewModel: ExportProgressViewModel?
    @State private var showProgress: Bool = false
    @State private var useDateRange: Bool = false

    @Environment(\.dismiss) private var dismiss

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
        .onChange(of: viewModel.startedJob?.id) { _, newId in
            guard let job = viewModel.startedJob, newId != nil else { return }
            progressViewModel = ExportProgressViewModel(
                job: job,
                repository: viewModel.repository
            )
            showProgress = true
        }
        .sheet(isPresented: $showProgress) {
            if let pvm = progressViewModel {
                ExportProgressView(viewModel: pvm)
            }
        }
        .alert("Export Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - iPhone layout (NavigationStack)

    private var iPhoneLayout: some View {
        NavigationStack {
            wizardForm
                .navigationTitle("New Export")
                .exportInlineTitleMode()
                .exportToolbarBackground()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityLabel("Cancel export wizard")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        startButton
                    }
                }
        }
        .presentationDetents([.large])
    }

    // MARK: - iPad layout (inline panel, no NavigationStack wrapper needed)

    private var iPadLayout: some View {
        wizardForm
            .navigationTitle("New Export")
            .exportToolbarBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel export wizard")
                }
                ToolbarItem(placement: .confirmationAction) {
                    startButton
                }
            }
    }

    // MARK: - Form

    private var wizardForm: some View {
        Form {
            entitySection
            formatSection
            dateRangeSection
            summarySection
        }
        .exportListStyle()
        .disabled(viewModel.isLoading)
    }

    // MARK: - Entity section

    private var entitySection: some View {
        Section {
            ForEach(ExportEntity.allCases, id: \.self) { entity in
                entityRow(entity)
            }
        } header: {
            Text("What to export")
        } footer: {
            Text("\"All data\" exports every table including customers, tickets, invoices, inventory, and more.")
        }
    }

    private func entityRow(_ entity: ExportEntity) -> some View {
        Button {
            viewModel.wizardEntity = entity
        } label: {
            HStack {
                Label(entity.displayName, systemImage: entity.systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                if viewModel.wizardEntity == entity {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(entity.displayName)
        .accessibilityValue(viewModel.wizardEntity == entity ? "Selected" : "")
        .accessibilityHint("Select \(entity.displayName) for export")
    }

    // MARK: - Format section

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $viewModel.wizardFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { fmt in
                    Label(fmt.displayName, systemImage: fmt.systemImage)
                        .tag(fmt)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Export format")
        } header: {
            Text("File format")
        } footer: {
            formatFooter
        }
    }

    private var formatFooter: some View {
        Group {
            switch viewModel.wizardFormat {
            case .csv:  Text("CSV — compatible with Excel, Numbers, and Google Sheets.")
            case .xlsx: Text("XLSX — native Excel format with formatting support.")
            case .json: Text("JSON — raw structured data for developers and integrations.")
            }
        }
        .font(.caption)
    }

    // MARK: - Date range section

    private var dateRangeSection: some View {
        Section {
            Toggle("Limit to date range", isOn: $useDateRange)
                .accessibilityLabel("Limit export to a date range")

            if useDateRange {
                DatePicker(
                    "From",
                    selection: Binding(
                        get: { viewModel.wizardDateFrom ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())! },
                        set: { viewModel.wizardDateFrom = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .accessibilityLabel("Export start date")

                DatePicker(
                    "To",
                    selection: Binding(
                        get: { viewModel.wizardDateTo ?? Date() },
                        set: { viewModel.wizardDateTo = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .accessibilityLabel("Export end date")
            }
        } header: {
            Text("Date range (optional)")
        } footer: {
            if !useDateRange {
                Text("Leave off to export all records regardless of date.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Summary section

    private var summarySection: some View {
        Section {
            HStack {
                Text("Entity")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.wizardEntity.displayName)
                    .bold()
            }
            HStack {
                Text("Format")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.wizardFormat.displayName)
                    .bold()
            }
            if useDateRange {
                HStack {
                    Text("Date range")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(dateRangeSummary)
                        .bold()
                }
            }
        } header: {
            Text("Summary")
        }
    }

    private var dateRangeSummary: String {
        let from = viewModel.wizardDateFrom?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        let to   = viewModel.wizardDateTo?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        return "\(from) – \(to)"
    }

    // MARK: - Start button

    @ViewBuilder
    private var startButton: some View {
        if viewModel.isLoading {
            ProgressView()
                .accessibilityLabel("Starting export…")
        } else {
            Button("Export") {
                Task { await startExport() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Start export")
            .accessibilityHint("Begins the \(viewModel.wizardEntity.displayName) \(viewModel.wizardFormat.displayName) export")
        }
    }

    // MARK: - Actions

    private func startExport() async {
        if viewModel.wizardEntity == .full {
            // Full tenant export requires passphrase — fall back to confirm sheet
            viewModel.requestFullTenantExport()
            dismiss()
        } else {
            // Per-domain export: local CSV for now (server async domain export
            // not yet exposed via a polled job endpoint)
            let filters = buildFilters()
            await viewModel.startDomainExport(entity: viewModel.wizardEntity.rawValue, filters: filters)
            dismiss()
        }
    }

    private func buildFilters() -> [String: String] {
        var filters: [String: String] = ["format": viewModel.wizardFormat.rawValue]
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        if useDateRange, let from = viewModel.wizardDateFrom {
            filters["date_from"] = df.string(from: from)
        }
        if useDateRange, let to = viewModel.wizardDateTo {
            filters["date_to"] = df.string(from: to)
        }
        return filters
    }
}

// MARK: - ExportWizardButton

/// Compact floating button that opens the export wizard.
public struct ExportWizardButton: View {
    public let viewModel: DataExportViewModel

    @State private var showWizard: Bool = false

    public init(viewModel: DataExportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Button {
            showWizard = true
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: $showWizard) {
            ExportWizardView(viewModel: viewModel)
        }
        .accessibilityLabel("Open export wizard")
    }
}
