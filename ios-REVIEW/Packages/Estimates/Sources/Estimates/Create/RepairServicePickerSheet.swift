#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §8.3 — Line items from repair-pricing services + inventory parts.
// Searches GET /api/v1/repair-pricing/services and returns selected services
// as EstimateDraft.LineItemDraft items, pre-filled from service default price.
//
// Used by EstimateCreateView "Add from catalog" button in the line items section.

@MainActor
@Observable
final class RepairServicePickerViewModel {
    var services: [RepairService] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var searchText: String = ""
    var selected: Set<Int64> = []

    private let api: APIClient
    private var searchTask: Task<Void, Never>?

    var filtered: [RepairService] {
        guard !searchText.isEmpty else { return services }
        let q = searchText.lowercased()
        return services.filter {
            $0.serviceName.lowercased().contains(q) ||
            ($0.family?.lowercased().contains(q) ?? false) ||
            ($0.model?.lowercased().contains(q) ?? false) ||
            ($0.partSku?.lowercased().contains(q) ?? false)
        }
    }

    init(api: APIClient) {
        self.api = api
    }

    func load() async {
        guard services.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            services = try await api.listRepairServices()
        } catch {
            errorMessage = "Could not load services: \(error.localizedDescription)"
        }
    }

    func onSearchChange(_ text: String) {
        searchText = text
    }

    func toggle(_ service: RepairService) {
        if selected.contains(service.id) {
            selected.remove(service.id)
        } else {
            selected.insert(service.id)
        }
    }

    /// Convert selected services to EstimateDraft.LineItemDraft rows.
    func buildLineItems() -> [EstimateDraft.LineItemDraft] {
        services
            .filter { selected.contains($0.id) }
            .map { svc in
                let priceDollars = Double(svc.defaultPriceCents) / 100.0
                return EstimateDraft.LineItemDraft(
                    description: svc.serviceName,
                    quantity: "1",
                    unitPrice: String(format: "%.2f", priceDollars)
                )
            }
    }
}

public struct RepairServicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: RepairServicePickerViewModel
    let onConfirm: ([EstimateDraft.LineItemDraft]) -> Void

    public init(api: APIClient, onConfirm: @escaping ([EstimateDraft.LineItemDraft]) -> Void) {
        _vm = State(wrappedValue: RepairServicePickerViewModel(api: api))
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Add from Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search services")
            .onChange(of: vm.searchText) { _, new in vm.onSearchChange(new) }
            .toolbar { toolbarContent }
            .task { await vm.load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Loading catalog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading repair services")
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, BrandSpacing.xl)
        } else if vm.filtered.isEmpty {
            ContentUnavailableView(
                vm.searchText.isEmpty ? "No services" : "No results",
                systemImage: "wrench.and.screwdriver",
                description: Text(vm.searchText.isEmpty ? "No repair services in catalog." : "Try a different search term.")
            )
        } else {
            List {
                ForEach(vm.filtered) { service in
                    ServiceRow(service: service, isSelected: vm.selected.contains(service.id)) {
                        vm.toggle(service)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .listRowInsets(EdgeInsets(top: BrandSpacing.sm, leading: BrandSpacing.base, bottom: BrandSpacing.sm, trailing: BrandSpacing.base))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel service selection")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Add \(vm.selected.count > 0 ? "(\(vm.selected.count))" : "")") {
                let items = vm.buildLineItems()
                onConfirm(items)
                dismiss()
            }
            .disabled(vm.selected.isEmpty)
            .fontWeight(.semibold)
            .accessibilityLabel("Add \(vm.selected.count) selected service\(vm.selected.count == 1 ? "" : "s")")
        }
    }
}

// MARK: - Row

private struct ServiceRow: View {
    let service: RepairService
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .animation(.spring(response: 0.2), value: isSelected)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(service.serviceName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    HStack(spacing: BrandSpacing.sm) {
                        if let family = service.family, !family.isEmpty {
                            Text(family)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        if let model = service.model, !model.isEmpty {
                            Text("•")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .font(.brandLabelSmall())
                            Text(model)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        if let minutes = service.estimatedMinutes, minutes > 0 {
                            Text("•")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .font(.brandLabelSmall())
                            Text("\(minutes) min")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }

                Spacer()

                Text(formatMoney(service.defaultPriceCents))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.serviceName), \(formatMoney(service.defaultPriceCents))")
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityHint("Toggle selection")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}
#endif
