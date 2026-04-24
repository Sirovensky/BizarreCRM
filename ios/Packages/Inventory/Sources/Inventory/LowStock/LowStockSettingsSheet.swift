#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - LowStockSettingsSheet

/// A sheet that lets users configure low-stock thresholds:
///   - Global default threshold (applies to all items without an override)
///   - Per-item threshold overrides (displayed for the provided item list)
///
/// All edits are returned via `onSave` as a new `LowStockThreshold` value —
/// the caller owns persistence.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showSettings) {
///     LowStockSettingsSheet(
///         items: inventoryItems,
///         current: currentThreshold,
///         onSave: { newThreshold in currentThreshold = newThreshold }
///     )
/// }
/// ```
public struct LowStockSettingsSheet: View {

    // MARK: Input

    private let items: [InventoryListItem]
    private let onSave: (LowStockThreshold) -> Void

    // MARK: State

    @State private var globalDefault: Int
    /// Tracks edited per-item values as strings for TextField binding.
    @State private var itemOverrideText: [Int64: String]
    /// Tracks which items have overrides toggled on.
    @State private var itemOverrideEnabled: [Int64: Bool]

    @Environment(\.dismiss) private var dismiss

    // MARK: Init

    public init(
        items: [InventoryListItem],
        current: LowStockThreshold,
        onSave: @escaping (LowStockThreshold) -> Void
    ) {
        self.items = items
        self.onSave = onSave
        _globalDefault = State(wrappedValue: current.globalDefault)
        var textMap: [Int64: String] = [:]
        var enabledMap: [Int64: Bool] = [:]
        for item in items {
            let override = current.overrides[item.id]
            enabledMap[item.id] = override != nil
            textMap[item.id] = override.map(String.init) ?? String(current.globalDefault)
        }
        _itemOverrideText = State(wrappedValue: textMap)
        _itemOverrideEnabled = State(wrappedValue: enabledMap)
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    globalSection
                    if !items.isEmpty {
                        perItemSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Low-stock thresholds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOrange)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.bizarreOrange)
                }
            }
        }
    }

    // MARK: - Global section

    private var globalSection: some View {
        Section {
            HStack {
                Text("Default threshold")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Stepper(
                    value: $globalDefault,
                    in: LowStockThreshold.minimumValue...LowStockThreshold.maximumValue
                ) {
                    Text("\(globalDefault)")
                        .font(.brandLabelLarge())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                }
                .labelsHidden()
                .accessibilityLabel("Global default threshold: \(globalDefault)")
            }
        } header: {
            Text("Global default")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        } footer: {
            Text("Items without a custom threshold alert when stock reaches this level.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Per-item section

    private var perItemSection: some View {
        Section {
            ForEach(items, id: \.id) { item in
                itemRow(item)
            }
        } header: {
            Text("Per-item overrides")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        } footer: {
            Text("Override the global default for individual items.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    @ViewBuilder
    private func itemRow(_ item: InventoryListItem) -> some View {
        let isEnabled = itemOverrideEnabled[item.id] ?? false
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Toggle(isOn: Binding(
                get: { itemOverrideEnabled[item.id] ?? false },
                set: { itemOverrideEnabled[item.id] = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    if let sku = item.sku, !sku.isEmpty {
                        Text("SKU \(sku)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .tint(.bizarreOrange)
            .accessibilityLabel("Custom threshold for \(item.displayName)")

            if isEnabled {
                overrideThresholdRow(item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .padding(.vertical, BrandSpacing.xxs)
    }

    private func overrideThresholdRow(_ item: InventoryListItem) -> some View {
        HStack {
            Text("Alert at")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Stepper(
                value: Binding(
                    get: { parsedOverride(for: item.id) },
                    set: { itemOverrideText[item.id] = String($0) }
                ),
                in: LowStockThreshold.minimumValue...LowStockThreshold.maximumValue
            ) {
                Text(itemOverrideText[item.id] ?? "")
                    .font(.brandLabelLarge())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOrange)
            }
            .labelsHidden()
            .accessibilityLabel("Override threshold for \(item.displayName): \(parsedOverride(for: item.id))")
        }
        .padding(.leading, BrandSpacing.lg)
    }

    // MARK: - Helpers

    private func parsedOverride(for itemId: Int64) -> Int {
        let raw = Int(itemOverrideText[itemId] ?? "") ?? globalDefault
        return LowStockThreshold.clampPublic(raw)
    }

    private func saveAndDismiss() {
        var result = LowStockThreshold(globalDefault: globalDefault, overrides: [:])
        for item in items {
            guard itemOverrideEnabled[item.id] == true else { continue }
            let value = parsedOverride(for: item.id)
            result = result.withOverride(itemId: item.id, threshold: value)
        }
        onSave(result)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let items: [InventoryListItem] = (1...5).map { i in
        let json: [String: Any] = [
            "id": Int64(i),
            "name": "Item \(i)",
            "sku": "SKU-\(i)",
            "in_stock": i * 2,
            "reorder_level": 5
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(InventoryListItem.self, from: data)
    }
    LowStockSettingsSheet(
        items: items,
        current: LowStockThreshold(globalDefault: 5, overrides: [1: 10, 3: 0]),
        onSave: { _ in }
    )
}
#endif
