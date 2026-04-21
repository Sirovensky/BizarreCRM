import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43.4 Service Part Mapping Sheet

/// Sheet opened from a "Map parts" button on a service row.
/// Allows selecting a primary SKU or configuring a multi-part bundle.
@MainActor
public struct ServicePartMappingSheet: View {
    @State private var vm: ServicePartMappingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let serviceName: String
    private let onSaved: (RepairService) -> Void

    public init(
        api: APIClient,
        serviceId: Int64,
        serviceName: String,
        onSaved: @escaping (RepairService) -> Void
    ) {
        self.serviceName = serviceName
        self.onSaved = onSaved
        _vm = State(wrappedValue: ServicePartMappingViewModel(api: api, serviceId: serviceId))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                mainContent
            }
            .navigationTitle("Map Parts")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("partMapping.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView().tint(.bizarreOrange)
                    } else {
                        Button("Save") {
                            Task { await saveAndDismiss() }
                        }
                        .bold()
                        .accessibilityIdentifier("partMapping.save")
                    }
                }
            }
            .onChange(of: vm.savedService) { _, new in
                guard let svc = new else { return }
                onSaved(svc)
                dismiss()
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                // Header
                serviceHeader
                    .padding(.horizontal, BrandSpacing.base)

                Divider()

                // Bundle toggle
                bundleToggle
                    .padding(.horizontal, BrandSpacing.base)

                Divider()

                if vm.isBundleMode {
                    bundleSection
                        .transition(reduceMotion ? .identity : .opacity)
                } else {
                    singleSkuSection
                        .transition(reduceMotion ? .identity : .opacity)
                }

                // Error banner
                if let err = vm.saveError {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding(BrandSpacing.base)
                        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, BrandSpacing.base)
                        .accessibilityLabel("Error: \(err)")
                }
            }
            .padding(.vertical, BrandSpacing.base)
        }
    }

    // MARK: - Sub-views

    private var serviceHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(serviceName)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityLabel("Service: \(serviceName)")
    }

    private var bundleToggle: some View {
        Toggle(isOn: $vm.isBundleMode) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Multi-part bundle")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Add multiple parts with individual quantities.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .tint(.bizarreOrange)
        .accessibilityLabel("Multi-part bundle mode")
        .accessibilityHint("When enabled you can add multiple SKUs with quantities")
    }

    // MARK: Single SKU mode

    private var singleSkuSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Primary Part")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            if let selected = vm.primarySku {
                selectedSkuBanner(item: selected) {
                    vm.primarySku = nil
                    vm.skuQuery = ""
                }
                .padding(.horizontal, BrandSpacing.base)
            }

            PartSkuPicker(
                query: $vm.skuQuery,
                results: vm.searchResults,
                isSearching: vm.isSearching,
                onSelect: { item in
                    vm.primarySku = item
                    vm.skuQuery = ""
                    vm.clearSearchResults()
                },
                onQueryChange: { vm.onSkuQueryChange($0) }
            )
        }
    }

    // MARK: Bundle mode

    private var bundleSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Bundle Parts")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            ForEach(vm.bundle.indices, id: \.self) { idx in
                BundleRowEditor(
                    row: vm.bundle[idx],
                    searchResults: vm.searchResults,
                    isSearching: vm.isSearching,
                    onSkuSearch: { vm.onSkuQueryChange($0) },
                    onSelectSku: { item in
                        vm.updateBundleRow(at: idx, skuId: item.sku)
                    },
                    onQtyChange: { q in
                        vm.updateBundleRow(at: idx, qty: q)
                    },
                    onRemove: {
                        vm.removeBundleRow(at: idx)
                    }
                )
                .padding(.horizontal, BrandSpacing.base)
                Divider().padding(.leading, BrandSpacing.base)
            }

            Button {
                vm.addBundleRow()
            } label: {
                Label("Add Part", systemImage: "plus.circle")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.xs)
            .accessibilityIdentifier("partMapping.addBundleRow")
        }
    }

    // MARK: - Helpers

    private func selectedSkuBanner(item: InventorySearchResult, onClear: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(item.sku)
                    .font(.brandMono(size: 11))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Remove selected part")
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func saveAndDismiss() async {
        await vm.save()
    }
}

// MARK: - Bundle Row Editor

private struct BundleRowEditor: View {
    let row: ServicePartBundle
    let searchResults: [InventorySearchResult]
    let isSearching: Bool
    let onSkuSearch: (String) -> Void
    let onSelectSku: (InventorySearchResult) -> Void
    let onQtyChange: (Int) -> Void
    let onRemove: () -> Void

    @State private var localQuery: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(row.skuId.isEmpty ? "New part" : row.skuId)
                    .font(.brandBodyMedium())
                    .foregroundStyle(row.skuId.isEmpty ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                    .accessibilityLabel(row.skuId.isEmpty ? "Empty SKU row" : "SKU: \(row.skuId)")
                Spacer()
                Stepper(
                    value: Binding(
                        get: { row.qty },
                        set: { onQtyChange($0) }
                    ),
                    in: 1...99
                ) {
                    Text("×\(row.qty)")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .fixedSize()
                .accessibilityLabel("Quantity \(row.qty)")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Remove this bundle row")
            }

            PartSkuPicker(
                query: $localQuery,
                results: row.skuId.isEmpty ? searchResults : [],
                isSearching: isSearching,
                onSelect: { item in
                    onSelectSku(item)
                    localQuery = item.sku
                },
                onQueryChange: onSkuSearch
            )
        }
    }
}
