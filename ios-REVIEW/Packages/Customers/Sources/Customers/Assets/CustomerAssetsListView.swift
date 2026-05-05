#if canImport(UIKit)
import SwiftUI
import DesignSystem

// §5.7 — Asset list section embedded in CustomerDetailView.
// Liquid Glass on navigation chrome only; list rows use solid card style.

public struct CustomerAssetsListView: View {

    @State private var vm: CustomerAssetsViewModel
    @State private var showingAdd: Bool = false
    @State private var detailAsset: CustomerAsset? = nil

    public init(repository: CustomerAssetsRepository, customerId: Int64) {
        _vm = State(wrappedValue: CustomerAssetsViewModel(
            repository: repository,
            customerId: customerId
        ))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header

            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BrandSpacing.sm)
            } else if vm.assets.isEmpty {
                emptyState
            } else {
                assetList
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .task { await vm.load() }
        .sheet(isPresented: $showingAdd) {
            AddAssetSheet(vm: vm)
        }
        .sheet(item: $detailAsset) { asset in
            AssetDetailSheet(asset: asset)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Assets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer(minLength: 0)
            Button {
                vm.prepareAddForm()
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Add asset")
        }
    }

    private var emptyState: some View {
        Text("No assets recorded.")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assetList: some View {
        ForEach(vm.assets) { asset in
            assetRow(asset)
        }
    }

    private func assetRow(_ asset: CustomerAsset) -> some View {
        Button {
            detailAsset = asset
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: assetIcon(for: asset.deviceType))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let type = asset.deviceType, !type.isEmpty {
                        Text(type)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let serial = asset.serial, !serial.isEmpty {
                        Text("S/N: \(serial)")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.caption)
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(assetAccessibilityLabel(asset))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                vm.remove(asset)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func assetIcon(for deviceType: String?) -> String {
        guard let t = deviceType?.lowercased() else { return "laptopcomputer" }
        if t.contains("phone") || t.contains("mobile") { return "iphone" }
        if t.contains("tablet") || t.contains("ipad") { return "ipad" }
        if t.contains("laptop") || t.contains("mac") { return "laptopcomputer" }
        if t.contains("watch") { return "applewatch" }
        if t.contains("tv") { return "tv" }
        return "desktopcomputer"
    }

    private func assetAccessibilityLabel(_ asset: CustomerAsset) -> String {
        var parts = [asset.name]
        if let t = asset.deviceType, !t.isEmpty { parts.append(t) }
        if let s = asset.serial, !s.isEmpty { parts.append("Serial \(s)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - AssetDetailSheet (tap-row → read-only detail)

struct AssetDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let asset: CustomerAsset

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    labelRow("Name", asset.name)
                    if let t = asset.deviceType, !t.isEmpty {
                        labelRow("Type", t)
                    }
                    if let c = asset.color, !c.isEmpty {
                        labelRow("Color", c)
                    }
                }
                Section("Identifiers") {
                    if let s = asset.serial, !s.isEmpty {
                        labelRow("Serial", s)
                    }
                    if let i = asset.imei, !i.isEmpty {
                        labelRow("IMEI", i)
                    }
                }
                if let notes = asset.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
                Section("Added") {
                    labelRow("Date", asset.createdAt)
                }
            }
            .navigationTitle(asset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .brandGlass(.regular, in: Capsule(), interactive: true)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func labelRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
    }
}
#endif
