import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43 Bulk Edit — Service Preset Import

/// ViewModel backing `ServicePresetImportView`.
///
/// Workflow:
/// 1. User pastes CSV text (or, in a future version, picks a file).
/// 2. VM parses the CSV synchronously using `PricingAdjustmentEngine.parseServiceCatalogCSV`.
/// 3. If there are valid rows, a preview list is shown.
/// 4. User taps "Import" → VM POSTs each valid row to `POST /repair-pricing/services`.
@MainActor
@Observable
public final class ServicePresetImportViewModel {

    // MARK: - Form state

    /// Raw CSV text entered/pasted by the user.
    public var csvText: String = ""

    // MARK: - Parse phase state

    public enum Phase: Sendable, Equatable {
        case idle
        case parsed(rows: [ServiceCatalogCSVRow], errors: [CSVParseError])
        case importing(progress: Int, total: Int)
        case done(successCount: Int, failCount: Int)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    public var isBusy: Bool {
        if case .importing = phase { return true }
        return false
    }

    // MARK: - Convenience accessors

    public var parsedRows: [ServiceCatalogCSVRow] {
        if case .parsed(let rows, _) = phase { return rows }
        return []
    }

    public var parseErrors: [CSVParseError] {
        if case .parsed(_, let errors) = phase { return errors }
        return []
    }

    public var canImport: Bool {
        if case .parsed(let rows, _) = phase { return !rows.isEmpty }
        return false
    }

    // MARK: - Private

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    /// Parse the current `csvText` and transition to `.parsed`.
    public func parseCSV() {
        let trimmed = csvText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed("Paste a CSV to import.")
            return
        }
        let (rows, errors) = PricingAdjustmentEngine.parseServiceCatalogCSV(trimmed)
        phase = .parsed(rows: rows, errors: errors)
    }

    /// Reset so the user can try again.
    public func reset() {
        csvText = ""
        phase = .idle
    }

    /// Import all successfully-parsed rows by POSTing to the server.
    ///
    /// Slug is derived from the name if not provided in the CSV
    /// (lowercased + spaces replaced with hyphens).
    public func importRows() async {
        guard case .parsed(let rows, _) = phase, !rows.isEmpty else { return }

        phase = .importing(progress: 0, total: rows.count)
        var successCount = 0
        var failCount = 0

        for (index, row) in rows.enumerated() {
            phase = .importing(progress: index, total: rows.count)
            let slug = row.slug ?? deriveSlug(from: row.name)
            do {
                _ = try await api.createRepairService(
                    name: row.name,
                    slug: slug,
                    category: row.category,
                    description: nil,
                    isActive: 1,
                    sortOrder: index
                )
                successCount += 1
            } catch {
                AppLog.ui.error("ServicePresetImport POST '\(row.name)' failed: \(error.localizedDescription, privacy: .public)")
                failCount += 1
            }
        }

        phase = .done(successCount: successCount, failCount: failCount)
    }

    // MARK: - Helpers

    private func deriveSlug(from name: String) -> String {
        name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}

// MARK: - View

/// Sheet for importing a service preset catalog from CSV.
///
/// iPad: two-column layout — paste area on the left, parsed preview on the right.
/// iPhone: stacked single column.
@MainActor
public struct ServicePresetImportView: View {
    @State private var vm: ServicePresetImportViewModel
    @Environment(\.dismiss) private var dismiss
    #if canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    private let onImported: (Int) -> Void

    public init(
        api: APIClient,
        onImported: @escaping (Int) -> Void = { _ in }
    ) {
        self.onImported = onImported
        _vm = State(wrappedValue: ServicePresetImportViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                mainContent
            }
            .navigationTitle("Import Service Catalog")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar { toolbarContent }
            .onChange(of: vm.phase) { _, newPhase in
                if case .done(let count, _) = newPhase {
                    onImported(count)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch vm.phase {
        case .idle, .failed:
            pasteForm
        case .parsed:
            #if canImport(UIKit)
            if hSizeClass == .regular {
                iPadParsedLayout
            } else {
                phoneParsedLayout
            }
            #else
            iPadParsedLayout
            #endif
        case .importing(let progress, let total):
            importingView(progress: progress, total: total)
        case .done(let success, let fail):
            doneView(successCount: success, failCount: fail)
        }
    }

    // MARK: - Paste Form

    private var pasteForm: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        Text("Expected columns (first row = header):")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("name, slug, category, labor_price")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.bizarreOrange)
                    }
                    .padding(.vertical, BrandSpacing.xs)
                } header: {
                    Text("Format")
                }
                .listRowBackground(Color.bizarreSurface1)

                Section {
                    TextEditor(text: $vm.csvText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("CSV text input")
                        .accessibilityIdentifier("csvImport.textEditor")
                } header: {
                    Text("CSV")
                } footer: {
                    if case .failed(let msg) = vm.phase {
                        Text(msg)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Parsed Layouts

    private var iPadParsedLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            pasteForm
                .frame(maxWidth: 340)
            Divider()
            parsedPreviewPanel
        }
    }

    private var phoneParsedLayout: some View {
        VStack(spacing: 0) {
            parsedPreviewPanel
        }
    }

    private var parsedPreviewPanel: some View {
        VStack(spacing: 0) {
            parsedSummaryBanner
            Divider()
            parsedTable
        }
    }

    private var parsedSummaryBanner: some View {
        HStack(spacing: BrandSpacing.md) {
            Label("\(vm.parsedRows.count) rows ready", systemImage: "checkmark.circle.fill")
                .font(.brandBodyMedium())
                .foregroundStyle(.green)
                .accessibilityLabel("\(vm.parsedRows.count) rows ready to import")
            if !vm.parseErrors.isEmpty {
                Label("\(vm.parseErrors.count) skipped", systemImage: "exclamationmark.triangle.fill")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("\(vm.parseErrors.count) rows skipped due to errors")
            }
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1)
    }

    private var parsedTable: some View {
        Table(vm.parsedRows) {
            TableColumn("Name") { row in
                Text(row.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            TableColumn("Category") { row in
                Text(row.category ?? "—")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            TableColumn("Labor Price") { row in
                Text(String(format: "$ %.2f", row.laborPrice))
                    .font(.brandBodyMedium().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .accessibilityLabel("Parsed service rows")
    }

    // MARK: - Importing / Done

    private func importingView(progress: Int, total: Int) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            ProgressView(value: Double(progress), total: Double(total))
                .tint(.bizarreOrange)
                .padding(.horizontal, BrandSpacing.xl)
            Text("Importing \(progress) / \(total)…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Importing services \(progress) of \(total)")
    }

    private func doneView(successCount: Int, failCount: Int) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: failCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(failCount == 0 ? .green : .bizarreError)
                .accessibilityHidden(true)
            Text("\(successCount) service\(successCount == 1 ? "" : "s") imported.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
            if failCount > 0 {
                Text("\(failCount) row\(failCount == 1 ? "" : "s") failed (likely duplicate slugs).")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }
            HStack(spacing: BrandSpacing.md) {
                Button("Import Another") { vm.reset() }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("csvImport.again")
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("csvImport.done")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(successCount) services imported\(failCount > 0 ? ", \(failCount) failed" : "")")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(vm.isBusy)
                .accessibilityIdentifier("csvImport.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
            if vm.isBusy {
                ProgressView().tint(.bizarreOrange)
            } else if vm.canImport {
                Button("Import") {
                    Task { await vm.importRows() }
                }
                .bold()
                .foregroundStyle(.bizarreOrange)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("csvImport.import")
            } else if case .idle = vm.phase {
                Button("Parse") {
                    vm.parseCSV()
                }
                .bold()
                .disabled(vm.csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundStyle(.bizarreOrange)
                .accessibilityIdentifier("csvImport.parse")
            }
        }

        // Back button when in parsed state
        if case .parsed = vm.phase {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit CSV") { vm.reset() }
                    .accessibilityIdentifier("csvImport.editCsv")
            }
        }
    }
}
