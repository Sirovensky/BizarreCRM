#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Shared form body for Create + Edit. Bindings are passed in so the view
/// doesn't own the view-model — both Create and Edit drive the same layout.
///
/// Mirrors `CustomerFormView`: grouped sections, focus chain across the
/// short-text fields, numeric keypads on the price / stock fields.
struct InventoryFormView: View {
    @Binding var name: String
    @Binding var sku: String
    @Binding var upc: String
    @Binding var itemType: String
    @Binding var category: String
    @Binding var manufacturer: String
    @Binding var description: String
    @Binding var costPrice: String
    @Binding var retailPrice: String
    @Binding var inStock: String
    @Binding var reorderLevel: String
    let isEdit: Bool
    let errorMessage: String?

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, sku, upc, category, manufacturer, description
        case costPrice, retailPrice, inStock, reorderLevel
    }

    var body: some View {
        Form {
            Section("Identity") {
                LabeledInventoryField("Name", text: $name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .sku }
                    .accessibilityLabel("Item name")
                    .accessibilityIdentifier("inventory.form.name")
                LabeledInventoryField("SKU", text: $sku, monospace: true)
                    .focused($focus, equals: .sku)
                    .submitLabel(.next)
                    .onSubmit { focus = .upc }
                    .accessibilityLabel("SKU")
                    .accessibilityIdentifier("inventory.form.sku")
                LabeledInventoryField("UPC / Barcode", text: $upc, monospace: true)
                    .focused($focus, equals: .upc)
                    .accessibilityLabel("UPC or barcode number")
                    .accessibilityIdentifier("inventory.form.upc")
                itemTypePicker
                    .accessibilityLabel("Item type")
                    .accessibilityIdentifier("inventory.form.itemType")
            }

            Section("Classification") {
                LabeledInventoryField("Category", text: $category)
                    .focused($focus, equals: .category)
                    .accessibilityLabel("Category")
                    .accessibilityIdentifier("inventory.form.category")
                LabeledInventoryField("Manufacturer", text: $manufacturer)
                    .focused($focus, equals: .manufacturer)
                    .accessibilityLabel("Manufacturer")
                    .accessibilityIdentifier("inventory.form.manufacturer")
            }

            Section("Pricing") {
                LabeledInventoryField("Cost price", text: $costPrice, keyboard: .decimalPad, prefix: "$")
                    .focused($focus, equals: .costPrice)
                    .accessibilityLabel("Cost price in dollars")
                    .accessibilityIdentifier("inventory.form.costPrice")
                LabeledInventoryField("Retail price", text: $retailPrice, keyboard: .decimalPad, prefix: "$")
                    .focused($focus, equals: .retailPrice)
                    .accessibilityLabel("Retail price in dollars")
                    .accessibilityIdentifier("inventory.form.retailPrice")
            }

            if !isEdit {
                // Stock fields on create only — adjust-stock on edit is a
                // separate endpoint so we don't offer it inline here.
                Section("Stock") {
                    LabeledInventoryField("In stock", text: $inStock, keyboard: .numberPad)
                        .focused($focus, equals: .inStock)
                        .accessibilityLabel("Quantity in stock")
                        .accessibilityIdentifier("inventory.form.inStock")
                    LabeledInventoryField("Reorder level", text: $reorderLevel, keyboard: .numberPad)
                        .focused($focus, equals: .reorderLevel)
                        .accessibilityLabel("Reorder threshold quantity")
                        .accessibilityIdentifier("inventory.form.reorderLevel")
                }
            } else {
                Section("Stock") {
                    LabeledInventoryField("Reorder level", text: $reorderLevel, keyboard: .numberPad)
                        .focused($focus, equals: .reorderLevel)
                        .accessibilityLabel("Reorder threshold quantity")
                        .accessibilityIdentifier("inventory.form.reorderLevel")
                }
            }

            Section("Description") {
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focus, equals: .description)
                    .accessibilityLabel("Item description")
                    .accessibilityIdentifier("inventory.form.description")
            }

            if let err = errorMessage {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var itemTypePicker: some View {
        Picker("Type", selection: $itemType) {
            Text("Product").tag("product")
            Text("Part").tag("part")
            Text("Service").tag("service")
        }
        .pickerStyle(.segmented)
        .disabled(isEdit)   // server allows update but keep the type stable in MVP
    }
}

/// Shared inline-label text field for inventory forms. Supports a leading
/// `$` symbol for price fields and monospace text for SKU / UPC.
struct LabeledInventoryField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var monospace: Bool = false
    var prefix: String? = nil

    init(_ label: String,
         text: Binding<String>,
         keyboard: UIKeyboardType = .default,
         monospace: Bool = false,
         prefix: String? = nil) {
        self.label = label
        self._text = text
        self.keyboard = keyboard
        self.monospace = monospace
        self.prefix = prefix
    }

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            if let prefix {
                Text(prefix)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            field
        }
    }

    @ViewBuilder
    private var field: some View {
        if monospace {
            TextField(label, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.brandMono(size: 15))
        } else {
            TextField(label, text: $text)
                .keyboardType(keyboard)
        }
    }
}
#endif
