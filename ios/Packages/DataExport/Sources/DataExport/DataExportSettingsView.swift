import SwiftUI
import DesignSystem
import Core

// MARK: - DataExportSettingsView

/// Settings → Danger → "Export all data" entry point.
/// iPhone: NavigationStack wizard. iPad: works as a panel in NavigationSplitView detail.
public struct DataExportSettingsView: View {

    @State private var viewModel: DataExportViewModel
    @State private var progressViewModel: ExportProgressViewModel?
    @State private var showProgress: Bool = false

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
                fullTenantRow
            } header: {
                Text("Full Backup")
            } footer: {
                Text("Creates an encrypted ZIP of all your data. Requires a passphrase you supply.")
            }

            Section {
                NavigationLink {
                    ScheduledExportListView(viewModel: viewModel)
                } label: {
                    Label("Scheduled Exports", systemImage: "clock.arrow.2.circlepath")
                }
                .accessibilityLabel("Scheduled Exports")
                .accessibilityHint("Configure daily, weekly, or monthly automatic exports")
            } header: {
                Text("Automation")
            }
        }
        .exportListStyle()
    }

    private var fullTenantRow: some View {
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
        .accessibilityHint("Triggers a full encrypted backup of all tenant data")
    }
}
