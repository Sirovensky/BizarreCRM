import SwiftUI

/// A bottom sheet that lets the user pick a date range and then export
/// visible audit log entries as a CSV file via `ShareLink`.
///
/// Usage (from `AuditLogListView` toolbar):
/// ```swift
/// .sheet(isPresented: $showExport) {
///     AuditLogExportSheet(entries: vm.entries)
/// }
/// ```
///
/// - The sheet is pure SwiftUI + Foundation (no UIKit imports).
/// - Composing and writing the CSV happens on a background `Task` when
///   the user taps "Export".
/// - The resulting file URL is handed to `ShareLink` once ready.
public struct AuditLogExportSheet: View {

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

    /// CSV file URL produced after tapping Export.
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
                exportSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Export CSV")
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
                    Label("Share CSV", systemImage: "square.and.arrow.up")
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
            .accessibilityLabel(isExporting ? "Preparing export" : "Export \(filteredEntries.count) entries")
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

        do {
            // Compose CSV on a non-isolated context to avoid blocking the main actor.
            let csv = await Task.detached(priority: .userInitiated) {
                AuditLogCSVComposer.compose(
                    entries: entriesToExport,
                    since: sinceFilter,
                    until: untilFilter
                )
            }.value

            let url = try AuditLogExportFileWriter.write(csvString: csv)
            exportURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
