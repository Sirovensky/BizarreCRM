import SwiftUI
import DesignSystem
import Core

// MARK: - DataExportSettingsView

/// Settings → Data → "Export" entry point.
/// iPhone: NavigationStack. iPad: NavigationSplitView detail panel.
public struct DataExportSettingsView: View {

    @State private var viewModel: DataExportViewModel
    @State private var progressViewModel: ExportProgressViewModel?
    @State private var showProgress: Bool = false
    @State private var showWizard: Bool = false

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
        .sheet(isPresented: $viewModel.showConfirmSheet) {
            FullExportConfirmSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showWizard) {
            ExportWizardView(viewModel: viewModel)
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
        .task { await viewModel.loadRateStatus() }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            exportList
                .navigationTitle("Data Export")
                .exportInlineTitleMode()
                .exportToolbarBackground()
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        exportList
            .navigationTitle("Data Export")
            .exportToolbarBackground()
    }

    // MARK: - Shared list

    private var exportList: some View {
        List {
            Section {
                // Full backup via async job
                Button {
                    viewModel.requestFullTenantExport()
                } label: {
                    HStack {
                        Label("Export all data", systemImage: "square.and.arrow.up.on.square.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Starting export")
                        }
                    }
                }
                .accessibilityLabel("Export all data")
                .accessibilityHint("Creates an encrypted backup of all tenant data")

                if let rate = viewModel.rateStatus {
                    rateStatusRow(rate)
                }
            } header: {
                Text("Full Backup")
            } footer: {
                Text("Creates an encrypted archive of all your data. Rate-limited to once per hour.")
            }

            Section {
                // Per-entity wizard
                Button {
                    showWizard = true
                } label: {
                    Label("Export wizard", systemImage: "wand.and.sparkles")
                }
                .accessibilityLabel("Export wizard")
                .accessibilityHint("Choose an entity, format, and date range for a targeted export")
            } header: {
                Text("Targeted Export")
            } footer: {
                Text("Select specific entity types (customers, tickets, invoices, etc.), format, and optional date range.")
            }

            Section {
                NavigationLink {
                    ExportScheduleListView(viewModel: viewModel)
                } label: {
                    Label("Export Schedules", systemImage: "clock.arrow.2.circlepath")
                }
                .accessibilityLabel("Export Schedules")
                .accessibilityHint("Manage recurring automatic exports")
            } header: {
                Text("Automation")
            }
        }
        .exportListStyle()
    }

    // MARK: - Rate status row

    private func rateStatusRow(_ rate: DataExportRateStatus) -> some View {
        HStack {
            if rate.allowed {
                Label("Export available now", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                let mins = (rate.nextAllowedInSeconds + 59) / 60
                Label("Next export available in \(mins) min", systemImage: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .accessibilityLabel(rate.allowed
            ? "Export available now"
            : "Next export available in \((rate.nextAllowedInSeconds + 59) / 60) minutes")
    }
}
