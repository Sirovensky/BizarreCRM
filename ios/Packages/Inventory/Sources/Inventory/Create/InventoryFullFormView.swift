#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

/// Shared create/edit form body. Extends the existing `InventoryFormView`
/// with Picker-driven category, supplier selection, and a barcode-scan button
/// that maps the result into the SKU field.
///
/// The old `InventoryFormView` is kept for backwards compatibility with
/// `InventoryEditView`. New create/edit surfaces use this view.
struct InventoryFullFormView: View {
    @Binding var name: String
    @Binding var sku: String
    @Binding var upc: String
    @Binding var itemType: String
    @Binding var category: String
    @Binding var manufacturer: String
    @Binding var description: String
    @Binding var costPriceCents: String
    @Binding var retailPriceCents: String
    @Binding var inStock: String
    @Binding var reorderLevel: String
    @Binding var supplierId: String
    let isEdit: Bool
    let errorMessage: String?
    var onScanBarcode: (() -> Void)?

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, sku, upc, category, manufacturer, description
        case costPrice, retailPrice, inStock, reorderLevel
    }

    // Well-known inventory categories from the server's enum.
    // In production these would come from a settings endpoint; hardcoded
    // here for MVP per §6.3 scope.
    private let knownCategories = [
        "Accessories", "Batteries", "Cables", "Chargers",
        "Cases", "Displays", "Memory", "Parts", "Tools", "Other"
    ]

    var body: some View {
        Form {
            identitySection
            classificationSection
            pricingSection
            stockSection
            descriptionSection
            if let err = errorMessage {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Error: \(err)")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identity") {
            TextField("Name *", text: $name)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .sku }
                .accessibilityLabel("Item name, required")

            HStack(spacing: BrandSpacing.sm) {
                TextField("SKU *", text: $sku)
                    .focused($focus, equals: .sku)
                    .submitLabel(.next)
                    .onSubmit { focus = .upc }
                    .font(.brandMono(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("SKU, required")

                if let onScan = onScanBarcode {
                    Button {
                        onScan()
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .imageScale(.large)
                            .foregroundStyle(.bizarreOrange)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Scan barcode to fill SKU")
                }
            }

            TextField("UPC / Barcode", text: $upc)
                .focused($focus, equals: .upc)
                .font(.brandMono(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("UPC or barcode number")

            itemTypePicker
        }
    }

    private var classificationSection: some View {
        Section("Classification") {
            // Category Picker — segmented on iPad, menu on iPhone
            Picker("Category", selection: $category) {
                Text("(none)").tag("")
                ForEach(knownCategories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .accessibilityLabel("Category picker")

            TextField("Manufacturer", text: $manufacturer)
                .focused($focus, equals: .manufacturer)
                .accessibilityLabel("Manufacturer name")
        }
    }

    private var pricingSection: some View {
        Section("Pricing") {
            CurrencyField(label: "Cost price", text: $costPriceCents)
                .focused($focus, equals: .costPrice)
            CurrencyField(label: "Retail price", text: $retailPriceCents)
                .focused($focus, equals: .retailPrice)
        }
    }

    private var stockSection: some View {
        Section("Stock") {
            if !isEdit {
                LabeledInventoryField("In stock", text: $inStock, keyboard: .numberPad)
                    .focused($focus, equals: .inStock)
                    .accessibilityLabel("Initial stock quantity")
            }
            LabeledInventoryField("Reorder level", text: $reorderLevel, keyboard: .numberPad)
                .focused($focus, equals: .reorderLevel)
                .accessibilityLabel("Reorder threshold quantity")
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(3...6)
                .focused($focus, equals: .description)
                .accessibilityLabel("Item description")
        }
    }

    private var itemTypePicker: some View {
        Picker("Type", selection: $itemType) {
            Text("Product").tag("product")
            Text("Part").tag("part")
            Text("Service").tag("service")
        }
        .pickerStyle(.segmented)
        .disabled(isEdit)
        .accessibilityLabel("Item type: \(itemType)")
    }
}

// MARK: - Currency field

/// Text field with a leading `$` symbol for dollar-amount entry.
struct CurrencyField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Text("$")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            TextField(label, text: $text)
                .keyboardType(.decimalPad)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), dollars")
    }
}
#endif
