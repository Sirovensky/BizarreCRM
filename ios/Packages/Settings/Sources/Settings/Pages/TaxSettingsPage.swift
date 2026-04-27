import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - Models

public struct TaxRate: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var rate: Double
    public var applyToAll: Bool
    public var isExempt: Bool
    public var isArchived: Bool

    public init(id: String, name: String, rate: Double,
                applyToAll: Bool = true, isExempt: Bool = false, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.rate = rate
        self.applyToAll = applyToAll
        self.isExempt = isExempt
        self.isArchived = isArchived
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class TaxSettingsViewModel: Sendable {

    var taxRates: [TaxRate] = []
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var showAddSheet: Bool = false
    var editingRate: TaxRate?

    // New/edit form fields
    var draftName: String = ""
    var draftRate: String = ""
    var draftApplyToAll: Bool = true
    var draftIsExempt: Bool = false

    var draftRateValue: Double? { Double(draftRate) }
    var isDraftValid: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty && draftRateValue != nil
    }

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let api else { return }
        do {
            let response = try await api.fetchTaxRates()
            taxRates = response.map {
                TaxRate(
                    id: $0.id, name: $0.name, rate: $0.rate,
                    applyToAll: $0.applyToAll ?? true,
                    isExempt: $0.isExempt ?? false,
                    isArchived: $0.isArchived ?? false
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginAdd() {
        draftName = ""
        draftRate = ""
        draftApplyToAll = true
        draftIsExempt = false
        editingRate = nil
        showAddSheet = true
    }

    func beginEdit(_ rate: TaxRate) {
        draftName = rate.name
        draftRate = String(rate.rate)
        draftApplyToAll = rate.applyToAll
        draftIsExempt = rate.isExempt
        editingRate = rate
        showAddSheet = true
    }

    func saveRate() async {
        guard let value = draftRateValue else { return }
        isSaving = true
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = TaxRateCreateDTO(
                name: draftName,
                rate: value,
                applyToAll: draftApplyToAll,
                isExempt: draftIsExempt
            )
            if let existing = editingRate {
                _ = try await api.updateTaxRate(id: existing.id, body)
            } else {
                _ = try await api.createTaxRate(body)
            }
            showAddSheet = false
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archiveRate(_ rate: TaxRate) async {
        guard let api else { return }
        do {
            let body = TaxRateCreateDTO(name: rate.name, rate: rate.rate, applyToAll: rate.applyToAll, isExempt: true)
            _ = try await api.updateTaxRate(id: rate.id, body)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct TaxSettingsPage: View {
    @State private var vm: TaxSettingsViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: TaxSettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            if vm.taxRates.isEmpty && !vm.isLoading {
                Section {
                    Text("No tax rates configured.")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("No tax rates configured")
                }
            }

            Section("Tax rates") {
                ForEach(vm.taxRates.filter { !$0.isArchived }) { rate in
                    HStack {
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text(rate.name)
                                .font(.brandTitleSmall())
                                .foregroundStyle(.bizarreOnSurface)
                            Text(String(format: "%.2f%%", rate.rate))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                        if rate.applyToAll {
                            Text("All")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreTeal)
                                .accessibilityLabel("Applies to all items")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { vm.beginEdit(rate) }
                    .accessibilityLabel("\(rate.name), \(rate.rate) percent")
                    .accessibilityHint("Double-tap to edit")
                    .swipeActions(edge: .trailing) {
                        Button("Archive", role: .destructive) {
                            Task { await vm.archiveRate(rate) }
                        }
                        .accessibilityLabel("Archive \(rate.name)")
                    }
                }
            }

            if let msg = vm.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(msg)")
                }
            }
        }
        .navigationTitle("Tax Settings")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.beginAdd()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add tax rate")
                .accessibilityIdentifier("tax.addRate")
            }
        }
        .sheet(isPresented: $vm.showAddSheet) {
            TaxRateFormSheet(vm: vm)
        }
        .task { await vm.load() }
    }
}

// MARK: - Tax rate form sheet

struct TaxRateFormSheet: View {
    @Bindable var vm: TaxSettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Rate") {
                    TextField("Name (e.g. State Tax)", text: $vm.draftName)
                        .accessibilityLabel("Tax rate name")
                        .accessibilityIdentifier("tax.draftName")
                    TextField("Rate %", text: $vm.draftRate)
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("Tax rate percent")
                        .accessibilityIdentifier("tax.draftRate")
                }
                Section("Options") {
                    Toggle("Apply to all items", isOn: $vm.draftApplyToAll)
                        .accessibilityIdentifier("tax.draftApplyToAll")
                    Toggle("Tax-exempt category", isOn: $vm.draftIsExempt)
                        .accessibilityIdentifier("tax.draftIsExempt")
                }
            }
            .navigationTitle(vm.editingRate == nil ? "New Tax Rate" : "Edit Tax Rate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showAddSheet = false }
                        .accessibilityIdentifier("tax.cancelRate")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await vm.saveRate() } }
                        .disabled(!vm.isDraftValid || vm.isSaving)
                        .accessibilityIdentifier("tax.saveRate")
                }
            }
        }
    }
}
