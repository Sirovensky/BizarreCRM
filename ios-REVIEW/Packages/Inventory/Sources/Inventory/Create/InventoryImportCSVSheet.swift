#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §6.1 Import CSV/JSON — paste → preview → confirm
// POST /api/v1/inventory/import-csv with row-level validation feedback.

struct ImportRow: Identifiable, Sendable {
    let id = UUID()
    let rowNumber: Int
    let name: String
    let sku: String
    let qty: String
    let price: String
    var validationError: String?
}

@MainActor
@Observable
final class InventoryImportCSVViewModel {
    var rawText: String = ""
    var previewRows: [ImportRow] = []
    var isSubmitting: Bool = false
    var errorMessage: String?
    var successMessage: String?
    var showingFilePicker: Bool = false

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    // Parse pasted/imported CSV text and produce preview rows.
    // Expected columns (order flexible if header present): name, sku, quantity, price
    func parseText(_ text: String) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { previewRows = []; return }

        // Detect if first line is header
        let firstLower = lines[0].lowercased()
        let hasHeader = firstLower.contains("name") || firstLower.contains("sku") || firstLower.contains("qty")
        let dataLines = hasHeader ? Array(lines.dropFirst()) : lines

        previewRows = dataLines.enumerated().map { (idx, line) in
            let cols = line.components(separatedBy: ",")
            // Flexible: at minimum expect 2 cols (name, sku)
            let name  = col(cols, 0)
            let sku   = col(cols, 1)
            let qty   = col(cols, 2)
            let price = col(cols, 3)
            var validErr: String?
            if name.isEmpty { validErr = "Name required" }
            else if sku.isEmpty { validErr = "SKU required" }
            else if let qtyInt = Int(qty), qtyInt < 0 { validErr = "Quantity must be ≥ 0" }
            else if !qty.isEmpty && Int(qty) == nil { validErr = "Quantity must be integer" }
            else if !price.isEmpty && Double(price) == nil { validErr = "Price must be a number" }
            return ImportRow(rowNumber: idx + (hasHeader ? 2 : 1),
                             name: name, sku: sku, qty: qty, price: price,
                             validationError: validErr)
        }
    }

    var validRowCount: Int { previewRows.filter { $0.validationError == nil }.count }
    var errorRowCount: Int { previewRows.filter { $0.validationError != nil }.count }

    func submit() async {
        guard !previewRows.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            // Build CSV with header from valid rows only.
            var csvLines = ["name,sku,quantity,retail_price"]
            for row in previewRows where row.validationError == nil {
                let line = "\(escaped(row.name)),\(escaped(row.sku)),\(row.qty),\(row.price)"
                csvLines.append(line)
            }
            let body = InventoryImportCSVRequest(csvData: csvLines.joined(separator: "\n"))
            try await api.importInventoryCSV(body)
            successMessage = "Imported \(validRowCount) item(s) successfully."
        } catch {
            AppLog.ui.error("InventoryImportCSV failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func col(_ cols: [String], _ idx: Int) -> String {
        guard idx < cols.count else { return "" }
        return cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func escaped(_ s: String) -> String {
        s.contains(",") || s.contains("\"") ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
    }
}

// MARK: - Sheet view

public struct InventoryImportCSVSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InventoryImportCSVViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: InventoryImportCSVViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    // Paste area
                    Section("CSV data") {
                        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                            Text("Paste CSV (name, sku, quantity, retail_price) or import a file.")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            TextEditor(text: $vm.rawText)
                                .font(.brandMono(size: 12))
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .accessibilityLabel("Paste CSV content here")
                                .onChange(of: vm.rawText) { _, new in vm.parseText(new) }
                        }
                        HStack {
                            Button {
                                vm.showingFilePicker = true
                            } label: {
                                Label("Import file", systemImage: "doc.badge.plus")
                            }
                            .accessibilityLabel("Import CSV or JSON file")

                            Spacer()

                            if !vm.rawText.isEmpty {
                                Button("Clear", role: .destructive) {
                                    vm.rawText = ""
                                    vm.previewRows = []
                                }
                                .accessibilityLabel("Clear CSV data")
                            }
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    // Preview
                    if !vm.previewRows.isEmpty {
                        Section {
                            HStack(spacing: BrandSpacing.md) {
                                statChip(label: "Total", value: "\(vm.previewRows.count)", color: .bizarreOnSurface)
                                statChip(label: "Valid", value: "\(vm.validRowCount)", color: .bizarreSuccess)
                                if vm.errorRowCount > 0 {
                                    statChip(label: "Errors", value: "\(vm.errorRowCount)", color: .bizarreError)
                                }
                            }
                            .padding(.vertical, BrandSpacing.xs)
                        } header: {
                            Text("Preview")
                        }
                        .listRowBackground(Color.bizarreSurface1)

                        Section("Rows") {
                            ForEach(vm.previewRows.prefix(50)) { row in
                                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                    HStack {
                                        Text("Row \(row.rowNumber): \(row.name.isEmpty ? "(no name)" : row.name)")
                                            .font(.brandBodyMedium())
                                            .foregroundStyle(row.validationError != nil ? .bizarreError : .bizarreOnSurface)
                                        Spacer()
                                        if let err = row.validationError {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundStyle(.bizarreError)
                                                .accessibilityLabel("Error: \(err)")
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.bizarreSuccess)
                                                .accessibilityLabel("Row valid")
                                        }
                                    }
                                    if !row.sku.isEmpty {
                                        Text("SKU: \(row.sku)  qty: \(row.qty.isEmpty ? "0" : row.qty)  price: \(row.price.isEmpty ? "—" : row.price)")
                                            .font(.brandMono(size: 12))
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                    }
                                    if let err = row.validationError {
                                        Text(err).font(.brandLabelSmall()).foregroundStyle(.bizarreError)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Row \(row.rowNumber): \(row.name)\(row.validationError != nil ? ", error: \(row.validationError!)" : ", valid")")
                            }
                            if vm.previewRows.count > 50 {
                                Text("… and \(vm.previewRows.count - 50) more rows")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }

                    if let err = vm.errorMessage {
                        Section {
                            Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel import")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await vm.submit()
                            if vm.successMessage != nil { dismiss() }
                        }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView().tint(.bizarreOrange)
                        } else {
                            Text("Import \(vm.validRowCount)")
                        }
                    }
                    .disabled(vm.validRowCount == 0 || vm.isSubmitting)
                    .accessibilityLabel("Import \(vm.validRowCount) valid rows")
                }
            }
            .fileImporter(
                isPresented: $vm.showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .json, .plainText]
            ) { result in
                if case let .success(url) = result {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        vm.rawText = text
                        vm.parseText(text)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(value)
                .font(.brandTitleMedium())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }
}

#endif
