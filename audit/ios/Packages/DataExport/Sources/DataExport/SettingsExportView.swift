import SwiftUI
import DesignSystem
import Core

// MARK: - SettingsExportViewModel

@Observable
@MainActor
public final class SettingsExportViewModel {

    // MARK: - State

    public private(set) var isExporting: Bool = false
    public private(set) var isImporting: Bool = false
    public private(set) var isLoadingTemplates: Bool = false
    public private(set) var isApplyingTemplate: Bool = false

    public private(set) var exportedPayload: SettingsExportPayload? = nil
    public private(set) var importResult: SettingsImportResult? = nil
    public private(set) var templates: [ShopTemplate] = []

    public private(set) var errorMessage: String? = nil
    public private(set) var successMessage: String? = nil

    // Picked JSON file for import
    public var importText: String = ""

    // MARK: - Dependencies

    private let repository: ExportRepository

    public init(repository: ExportRepository) {
        self.repository = repository
    }

    // MARK: - Export

    public func exportSettings() async {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }
        do {
            exportedPayload = try await repository.fetchSettingsExport()
            successMessage = "Settings exported — \(exportedPayload?.settings.count ?? 0) keys"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func exportedJSON() -> String? {
        guard let payload = exportedPayload else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Import

    public func importSettings() async {
        guard !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Paste or load a settings JSON before importing."
            return
        }
        guard let data = importText.data(using: .utf8) else {
            errorMessage = "Invalid UTF-8 content."
            return
        }

        let decoded: SettingsExportPayload
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoded = try decoder.decode(SettingsExportPayload.self, from: data)
        } catch {
            // Also try flat { key: value } object
            do {
                let flat = try JSONDecoder().decode([String: String].self, from: data)
                await performImport(flat)
                return
            } catch {
                errorMessage = "Could not parse settings JSON: \(error.localizedDescription)"
                return
            }
        }

        await performImport(decoded.settings)
    }

    private func performImport(_ payload: [String: String]) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            importResult = try await repository.importSettings(payload: payload)
            successMessage = "Imported \(importResult?.imported ?? 0) settings (\(importResult?.skipped.count ?? 0) skipped)"
            importText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Templates

    public func loadTemplates() async {
        isLoadingTemplates = true
        defer { isLoadingTemplates = false }
        do {
            templates = try await repository.fetchShopTemplates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func applyTemplate(id: String) async {
        isApplyingTemplate = true
        errorMessage = nil
        defer { isApplyingTemplate = false }
        do {
            try await repository.applyShopTemplate(id: id)
            successMessage = "Template applied"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - SettingsExportView

/// Settings → Backup & Restore — export/import settings JSON + apply shop templates.
/// iPhone: NavigationStack. iPad: detail panel in NavigationSplitView.
public struct SettingsExportView: View {

    @State private var viewModel: SettingsExportViewModel
    @State private var showShareSheet: Bool = false
    @State private var showImportInput: Bool = false
    @State private var confirmTemplateId: String? = nil

    public init(viewModel: SettingsExportViewModel) {
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
        .task { await viewModel.loadTemplates() }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearMessages() } }
        )) {
            Button("OK") { viewModel.clearMessages() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Success", isPresented: Binding(
            get: { viewModel.successMessage != nil },
            set: { if !$0 { viewModel.clearMessages() } }
        )) {
            Button("OK") { viewModel.clearMessages() }
        } message: {
            Text(viewModel.successMessage ?? "")
        }
        .confirmationDialog("Apply template?", isPresented: Binding(
            get: { confirmTemplateId != nil },
            set: { if !$0 { confirmTemplateId = nil } }
        ), titleVisibility: .visible) {
            if let tid = confirmTemplateId {
                Button("Apply") {
                    Task { await viewModel.applyTemplate(id: tid) }
                    confirmTemplateId = nil
                }
                Button("Cancel", role: .cancel) { confirmTemplateId = nil }
            }
        } message: {
            if let tid = confirmTemplateId,
               let tmpl = viewModel.templates.first(where: { $0.id == tid }) {
                Text("This will update \(tmpl.settingsCount) settings. Existing settings not covered by the template will be unchanged.")
            }
        }
        .sheet(isPresented: $showImportInput) {
            importSheet
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            settingsList
                .navigationTitle("Settings Backup")
                .exportInlineTitleMode()
                .exportToolbarBackground()
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        settingsList
            .navigationTitle("Settings Backup")
            .exportToolbarBackground()
    }

    // MARK: - Settings list

    private var settingsList: some View {
        List {
            Section {
                exportRow
                importRow
            } header: {
                Text("Backup & Restore")
            } footer: {
                Text("Export your shop settings to a JSON file and restore them on another device or after a reinstall.")
            }

            if !viewModel.templates.isEmpty {
                Section {
                    if viewModel.isLoadingTemplates {
                        ProgressView("Loading templates…")
                            .accessibilityLabel("Loading templates")
                    } else {
                        ForEach(viewModel.templates) { template in
                            templateRow(template)
                        }
                    }
                } header: {
                    Text("Shop Templates")
                } footer: {
                    Text("Applying a template updates settings to recommended defaults for your shop type. Your customizations outside the template are not affected.")
                }
            }
        }
        .exportListStyle()
    }

    // MARK: - Export row

    private var exportRow: some View {
        Button {
            Task { await export() }
        } label: {
            HStack {
                Label("Export settings", systemImage: "arrow.up.doc.fill")
                Spacer()
                if viewModel.isExporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Exporting settings")
                }
            }
        }
        .disabled(viewModel.isExporting)
        .accessibilityLabel("Export settings")
        .accessibilityHint("Downloads a JSON backup of all shop settings")
    }

    // MARK: - Import row

    private var importRow: some View {
        Button {
            showImportInput = true
        } label: {
            HStack {
                Label("Import settings", systemImage: "arrow.down.doc.fill")
                Spacer()
                if viewModel.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Importing settings")
                }
            }
        }
        .disabled(viewModel.isImporting)
        .accessibilityLabel("Import settings")
        .accessibilityHint("Paste or load a settings JSON file to restore settings")
    }

    // MARK: - Template row

    private func templateRow(_ template: ShopTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(template.label)
                    .font(.body)
                Spacer()
                Button("Apply") {
                    confirmTemplateId = template.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isApplyingTemplate)
                .accessibilityLabel("Apply \(template.label) template")
            }
            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(template.settingsCount) settings")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.label), \(template.description), \(template.settingsCount) settings")
    }

    // MARK: - Import sheet

    private var importSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Paste the settings JSON exported from another device or backup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextEditor(text: $viewModel.importText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .accessibilityLabel("Settings JSON input")

                if let result = viewModel.importResult {
                    Text("Imported: \(result.imported), Skipped: \(result.skipped.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await viewModel.importSettings()
                        if viewModel.errorMessage == nil {
                            showImportInput = false
                        }
                    }
                } label: {
                    if viewModel.isImporting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Import")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.brandGlassProminent)
                .tint(Color.accentColor)
                .disabled(viewModel.isImporting || viewModel.importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                .padding(.bottom)
                .accessibilityLabel("Import settings")
            }
            .navigationTitle("Import Settings")
            .exportInlineTitleMode()
            .exportToolbarBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportInput = false }
                        .accessibilityLabel("Cancel import")
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Actions

    private func export() async {
        await viewModel.exportSettings()
        guard let json = viewModel.exportedJSON() else { return }
        showShareSheet = true
        let _ = json // will be used by sheet below
    }
}

// MARK: - SettingsExportShareSheet

/// ShareLink for the exported settings JSON string.
public struct SettingsExportShareSheet: View {
    public let json: String
    public let filename: String

    public init(json: String, filename: String = "bizarrecrm-settings.json") {
        self.json = json
        self.filename = filename
    }

    public var body: some View {
        let data = json.data(using: .utf8) ?? Data()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        let _ = try? data.write(to: url)

        ShareLink(
            item: url,
            subject: Text("BizarreCRM Settings Backup"),
            message: Text("Settings backup exported from BizarreCRM")
        ) {
            Label("Share settings JSON", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(Color.accentColor)
        .padding()
        .presentationDetents([.height(200)])
        .accessibilityLabel("Share settings backup JSON")
    }
}
