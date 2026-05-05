#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.16 — Admin screen where a manager picks the 3 quick-sale hotkeys.
public struct QuickSaleSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var hotkeys:   QuickSaleHotkeys = .empty
    @State private var isSaving:  Bool             = false
    @State private var editingIdx: Int?             = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    Section {
                        ForEach(0..<3, id: \.self) { idx in
                            slotRow(idx)
                        }
                    } header: {
                        Text("Quick-sale tiles")
                    } footer: {
                        Text("These 3 tiles appear above the cart for one-tap adds. Leave empty to hide a tile.")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Quick-Sale Hotkeys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await persist() }
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("quickSaleSettings.save")
                    }
                }
            }
            .sheet(item: Binding<QuickSaleEditIndex?>(
                get: { editingIdx.map { QuickSaleEditIndex(index: $0) } },
                set: { editingIdx = $0?.index }
            )) { editIndex in
                QuickSaleHotkeyEditorSheet(
                    hotkey: hotkeys.slots[editIndex.index],
                    onSave: { newHotkey in
                        hotkeys = hotkeys.setting(newHotkey, at: editIndex.index)
                    }
                )
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Slot row

    private func slotRow(_ idx: Int) -> some View {
        Button {
            editingIdx = idx
        } label: {
            HStack {
                Image(systemName: "number.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                if let hotkey = hotkeys.slots[idx] {
                    VStack(alignment: .leading) {
                        Text(hotkey.displayName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Text(CartMath.formatCents(hotkey.unitPriceCents))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                } else {
                    Text("Empty — tap to configure")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("Slot \(idx + 1): \(hotkeys.slots[idx]?.displayName ?? "empty")")
        .accessibilityHint("Double tap to edit")
        .accessibilityIdentifier("quickSaleSettings.slot.\(idx)")
    }

    // MARK: - Persistence

    private func load() async {
        hotkeys = await QuickSaleHotkeyStore.shared.load()
    }

    private func persist() async {
        isSaving = true
        await QuickSaleHotkeyStore.shared.save(hotkeys)
        isSaving = false
        dismiss()
    }
}

// MARK: - Inline editor sheet

private struct QuickSaleHotkeyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let hotkey: QuickSaleHotkey?
    let onSave: (QuickSaleHotkey?) -> Void

    @State private var name:       String = ""
    @State private var priceText:  String = ""
    @State private var sku:        String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Tile label") {
                        TextField("e.g. Screen Protector", text: $name)
                            .accessibilityIdentifier("quickSaleEditor.name")
                    }
                    Section("Price (dollars)") {
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("quickSaleEditor.price")
                    }
                    Section("SKU (optional)") {
                        TextField("SKU", text: $sku)
                            .accessibilityIdentifier("quickSaleEditor.sku")
                    }
                    if hotkey != nil {
                        Section {
                            Button("Clear this slot", role: .destructive) {
                                onSave(nil)
                                dismiss()
                            }
                            .accessibilityIdentifier("quickSaleEditor.clear")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(hotkey == nil ? "Add Hotkey" : "Edit Hotkey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let cents = Int((Double(priceText) ?? 0) * 100)
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let h = QuickSaleHotkey(
                            sku:            sku.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sku,
                            displayName:    name.trimmingCharacters(in: .whitespaces),
                            unitPriceCents: cents
                        )
                        onSave(h)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("quickSaleEditor.done")
                }
            }
        }
        .onAppear {
            if let h = hotkey {
                name      = h.displayName
                priceText = String(format: "%.2f", Double(h.unitPriceCents) / 100)
                sku       = h.sku ?? ""
            }
        }
    }
}

// MARK: - Helper for sheet binding

private struct QuickSaleEditIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

private extension Binding {
    func map<T>(get: @escaping (Value) -> T, set: @escaping (T) -> Value) -> Binding<T> {
        Binding<T>(get: { get(wrappedValue) }, set: { wrappedValue = set($0) })
    }
}
#endif
