import SwiftUI
import DesignSystem

// MARK: - DomainExportMenu

/// Contextual "Export as CSV" option for any list view.
/// Pass the current entity name and active filter dictionary.
/// Shows a ShareLink with the generated CSV, or triggers a server-side export.
public struct DomainExportMenu: View {

    public let entity: String
    public let filter: [String: String]
    public let rows: [[String]]
    public let columns: [String]

    @State private var viewModel: DataExportViewModel
    @State private var showLocalCSVShare: Bool = false
    @State private var showProgress: Bool = false
    @State private var progressViewModel: ExportProgressViewModel?
    @State private var localCSV: String = ""

    public init(
        entity: String,
        filter: [String: String] = [:],
        rows: [[String]] = [],
        columns: [String] = [],
        viewModel: DataExportViewModel
    ) {
        self.entity = entity
        self.filter = filter
        self.rows = rows
        self.columns = columns
        self._viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        Menu {
            // Local CSV from in-memory rows (fast, offline-capable)
            if !rows.isEmpty {
                Button {
                    localCSV = CSVComposer.compose(rows: rows, columns: columns)
                    showLocalCSVShare = true
                } label: {
                    Label("Export current page as CSV", systemImage: "tablecells")
                }
                .accessibilityLabel("Export current page as CSV")
                .accessibilityHint("Generates a CSV from the currently loaded rows")
            }

            // Server-side export (all filtered rows)
            Button {
                Task { await startServerExport() }
            } label: {
                Label("Export all \(entity) (filtered) via server", systemImage: "arrow.down.circle")
            }
            .accessibilityLabel("Export all \(entity) via server")
            .accessibilityHint("Requests a server-generated export of all filtered \(entity)")
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .accessibilityLabel("Export \(entity)")
        }
        .sheet(isPresented: $showLocalCSVShare) {
            localCSVShareSheet
        }
        .sheet(isPresented: $showProgress) {
            if let pvm = progressViewModel {
                ExportProgressView(viewModel: pvm)
            }
        }
        .onChange(of: viewModel.startedJob?.id) { _, newId in
            guard let job = viewModel.startedJob, newId != nil else { return }
            progressViewModel = ExportProgressViewModel(job: job, repository: viewModel.repository)
            showProgress = true
        }
    }

    // MARK: - Local CSV share sheet

    @ViewBuilder
    private var localCSVShareSheet: some View {
        let csvData = localCSV.data(using: .utf8) ?? Data()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(entity)-export.csv")
        let _ = try? csvData.write(to: tempURL)

        ShareLink(
            item: tempURL,
            subject: Text("\(entity) Export"),
            message: Text("Exported from BizarreCRM")
        ) {
            Label("Share CSV", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandGlassProminent)
        .padding()
        .presentationDetents([.height(200)])
    }

    // MARK: - Server export

    private func startServerExport() async {
        await viewModel.startDomainExport(entity: entity, filters: filter)
    }
}
