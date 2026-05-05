import SwiftUI

/// A bottom sheet that lets the user pick a date range and export
/// visible audit log entries as CSV or PDF (court-evidence format).
///
/// Usage (from `AuditLogListView` toolbar):
/// ```swift
/// .sheet(isPresented: $showExport) {
///     AuditLogExportSheet(entries: vm.entries)
/// }
/// ```
///
/// - CSV: pure SwiftUI + Foundation, cross-platform.
/// - PDF: §50.3 court-evidence format; UIKit-guarded (`AuditLogPDFComposer`).
public struct AuditLogExportSheet: View {

    // MARK: - Export format

    public enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case pdf = "PDF (Court Evidence)"
        public var id: String { rawValue }
    }

    // MARK: - Input

    /// All currently-loaded entries (pre-filter by the caller if desired).
    private let entries: [AuditLogEntry]

    // MARK: - State

    /// Lower bound of the custom date range. Defaults to 30 days ago.
    @State private var since: Date = Calendar.current.date(
        byAdding: .day, value: -30, to: Date()
    ) ?? Date()

    /// Upper bound of the custom date range. Defaults to now.
    @State private var until: Date = Date()

    /// Whether the date-range filter is active.
    @State private var filterByDateRange: Bool = false

    /// Selected export format.
    @State private var exportFormat: ExportFormat = .csv

    /// File URL produced after tapping Export.
    @State private var exportURL: URL?

    /// Transient error shown if writing fails.
    @State private var errorMessage: String?

    /// Indicates an in-progress compose + write operation.
    @State private var isExporting: Bool = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    public init(entries: [AuditLogEntry]) {
        self.entries = entries
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                entrySummarySection
                dateRangeSection
                formatSection
                exportSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Export Audit Log")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $exportFormat) {
                ForEach(ExportFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.menu)
            .tint(.bizarreOrange)
            .onChange(of: exportFormat) { _, _ in
                // Reset prior export when format changes.
                exportURL = nil
                errorMessage = nil
            }
            .accessibilityIdentifier("export.formatPicker")
            if exportFormat == .pdf {
                Label("Court-evidence PDF includes cover page, paginated entry table, and signature block.",
                      systemImage: "info.circle")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        } header: {
            Text("Format")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var entrySummarySection: some View {
        Section {
            HStack {
                Text("Entries available")
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text("\(filteredEntries.count)")
                    .monospacedDigit()
                    .foregroundStyle(filteredEntries.isEmpty ? .bizarreError : .bizarreOrange)
                    .fontWeight(.semibold)
            }
        } header: {
            Text("Preview")
        }
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(filteredEntries.count) entries will be exported")
    }

    private var dateRangeSection: some View {
        Section {
            Toggle("Filter by date range", isOn: $filterByDateRange)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("export.dateRangeToggle")

            if filterByDateRange {
                DatePicker(
                    "From",
                    selection: $since,
                    in: ...until,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("export.datePicker.from")

                DatePicker(
                    "To",
                    selection: $until,
                    in: since...,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("export.datePicker.to")
            }
        } header: {
            Text("Date Range")
        }
        .listRowBackground(Color.bizarreSurface1)
        .animation(.easeInOut(duration: 0.2), value: filterByDateRange)
    }

    @ViewBuilder
    private var exportSection: some View {
        Section {
            if let url = exportURL {
                // ShareLink is available once the file is ready.
                ShareLink(
                    item: url,
                    subject: Text("Audit Log Export"),
                    message: Text("Exported from BizarreCRM on \(Date().formatted(.dateTime.year().month().day()))")
                ) {
                    Label(exportFormat == .pdf ? "Share PDF" : "Share CSV",
                          systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .font(.brandBodyMedium().weight(.semibold))
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityIdentifier("export.shareLink")
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("export.errorLabel")
            }

            Button {
                Task { await buildExport() }
            } label: {
                HStack {
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing…")
                            .font(.brandBodyMedium())
                    } else {
                        Text(exportURL == nil ? "Export" : "Re-export")
                            .font(.brandBodyMedium().weight(.semibold))
                    }
                    Spacer()
                }
            }
            .disabled(isExporting || filteredEntries.isEmpty)
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("export.exportButton")
            .accessibilityLabel(isExporting ? "Preparing export" : "Export \(filteredEntries.count) entries as \(exportFormat.rawValue)")
        } header: {
            Text("Export")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Computed helpers

    /// Entries filtered by the active date-range (if enabled).
    private var filteredEntries: [AuditLogEntry] {
        guard filterByDateRange else { return entries }
        return entries.filter { $0.createdAt >= since && $0.createdAt <= until }
    }

    // MARK: - Actions

    @MainActor
    private func buildExport() async {
        isExporting = true
        exportURL = nil
        errorMessage = nil
        defer { isExporting = false }

        let entriesToExport = filteredEntries
        let sinceFilter: Date? = filterByDateRange ? since : nil
        let untilFilter: Date? = filterByDateRange ? until : nil
        let format = exportFormat

        do {
            let url: URL = try await {
                switch format {
                case .csv:
                    let csv = AuditLogCSVComposer.compose(
                        entries: entriesToExport,
                        since: sinceFilter,
                        until: untilFilter
                    )
                    return try AuditLogExportFileWriter.write(csvString: csv)
                case .pdf:
                    return try AuditLogPDFComposer.compose(
                        entries: entriesToExport,
                        since: sinceFilter,
                        until: untilFilter
                    )
                }
            }()
            exportURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
