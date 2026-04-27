#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Asset Manager View
//
// Admin CRUD for loaner / physical assets.
// Backs Settings → Inventory → Loaner Assets.
// Issue/return flows are invoked from Ticket detail (Agent 3).

// MARK: - List ViewModel

@MainActor
@Observable
public final class AssetManagerViewModel {

    public private(set) var assets: [InventoryAsset] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var showCreate = false
    public var editingAsset: InventoryAsset?
    public var deletingAsset: InventoryAsset?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            assets = try await api.listAssets()
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Failed to load assets."
            AppLog.ui.error("AssetManager load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func delete(_ asset: InventoryAsset) async {
        do {
            try await api.deleteAsset(id: asset.id)
            assets.removeAll { $0.id == asset.id }
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Delete failed."
        }
    }
}

// MARK: - List View

/// Admin list: all loaner devices with status chips and CRUD actions.
public struct AssetManagerView: View {
    @State private var vm: AssetManagerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: AssetManagerViewModel(api: api))
    }

    public var body: some View {
        Group {
            if vm.isLoading && vm.assets.isEmpty {
                ProgressView("Loading assets…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.assets.isEmpty && vm.errorMessage == nil {
                ContentUnavailableView(
                    "No loaner assets",
                    systemImage: "shippingbox",
                    description: Text("Add a loaner device to start issuing it to customers.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Loaner Assets")
        .toolbar { toolbar }
        .sheet(isPresented: $vm.showCreate) {
            AssetEditorSheet(api: api, asset: nil) {
                Task { await vm.load() }
            }
        }
        .sheet(item: $vm.editingAsset) { asset in
            AssetEditorSheet(api: api, asset: asset) {
                Task { await vm.load() }
            }
        }
        .confirmationDialog(
            "Delete \"\(vm.deletingAsset?.name ?? "")\"?",
            isPresented: .init(get: { vm.deletingAsset != nil }, set: { if !$0 { vm.deletingAsset = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let a = vm.deletingAsset { Task { await vm.delete(a) } }
                vm.deletingAsset = nil
            }
            Button("Cancel", role: .cancel) { vm.deletingAsset = nil }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .init(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: List

    private var list: some View {
        List(vm.assets) { asset in
            assetRow(asset)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        vm.deletingAsset = asset
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        vm.editingAsset = asset
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.bizarrePrimary)
                }
                .contextMenu {
                    Button("Edit") { vm.editingAsset = asset }
                    Button("Delete", role: .destructive) { vm.deletingAsset = asset }
                }
        }
        .listStyle(.insetGrouped)
    }

    private func assetRow(_ asset: InventoryAsset) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "shippingbox")
                .foregroundStyle(assetStatusColor(asset.status))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(asset.name)
                    .font(.bizarreBody)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.bizarreTextPrimary)

                HStack(spacing: BrandSpacing.xs) {
                    if let serial = asset.serial {
                        Text(serial)
                            .font(.bizarreMono(size: 12))
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                    if let condition = asset.condition {
                        Text("· \(condition)")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                }

                if let loanedTo = asset.loanedTo {
                    Label("Loaned to \(loanedTo)", systemImage: "person")
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreWarning)
                }
            }

            Spacer()

            statusChip(asset.status)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: asset))
    }

    private func statusChip(_ status: AssetStatus) -> some View {
        Text(status.displayName)
            .font(.bizarreCaption)
            .fontWeight(.semibold)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Capsule().fill(assetStatusColor(status).opacity(0.15)))
            .foregroundStyle(assetStatusColor(status))
    }

    private func assetStatusColor(_ status: AssetStatus) -> Color {
        switch status {
        case .available: return .bizarreSuccess
        case .loaned:    return .bizarreWarning
        case .retired:   return .bizarreTextSecondary
        }
    }

    private func accessibilityLabel(for asset: InventoryAsset) -> String {
        var parts = [asset.name, asset.status.displayName]
        if let serial = asset.serial { parts.append("Serial \(serial)") }
        if let t = asset.loanedTo { parts.append("Loaned to \(t)") }
        return parts.joined(separator: ". ")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.showCreate = true
            } label: {
                Label("Add asset", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityLabel("Add loaner asset")
        }
    }
}

// MARK: - Editor Sheet

/// Create or edit a loaner asset.
public struct AssetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let api: APIClient
    private let existingAsset: InventoryAsset?
    private let onSave: () -> Void

    @State private var name = ""
    @State private var serial = ""
    @State private var imei = ""
    @State private var condition = ""
    @State private var status: AssetStatus = .available
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    public init(api: APIClient, asset: InventoryAsset?, onSave: @escaping () -> Void) {
        self.api = api
        self.existingAsset = asset
        self.onSave = onSave

        if let a = asset {
            _name = State(initialValue: a.name)
            _serial = State(initialValue: a.serial ?? "")
            _imei = State(initialValue: a.imei ?? "")
            _condition = State(initialValue: a.condition ?? "")
            _status = State(initialValue: a.status)
            _notes = State(initialValue: a.notes ?? "")
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    TextField("Name (required)", text: $name)
                        .textContentType(.name)
                    TextField("Serial number", text: $serial)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                    TextField("IMEI (admin only)", text: $imei)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.bizarreMono(size: 15))
                }

                Section("Condition & Status") {
                    TextField("Condition (e.g. Good, Minor scratch)", text: $condition)
                    Picker("Status", selection: $status) {
                        ForEach(AssetStatus.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.bizarreError)
                    }
                }
            }
            .navigationTitle(existingAsset == nil ? "New Asset" : "Edit Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let request = UpsertAssetRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            serial: serial.isEmpty ? nil : serial,
            imei: imei.isEmpty ? nil : imei,
            condition: condition.isEmpty ? nil : condition,
            status: status,
            notes: notes.isEmpty ? nil : notes
        )

        do {
            if let existing = existingAsset {
                _ = try await api.updateAsset(id: existing.id, request)
            } else {
                _ = try await api.createAsset(request)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Save failed."
        }
    }
}

// Swift 6 @Observable workaround — expose api to child sheets via init capture.
// AssetEditorSheet receives api directly from the call site.

#endif
