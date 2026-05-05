#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

/// Shared create/edit form body. Extends the existing `InventoryFormView`
/// with Picker-driven category, supplier selection, a barcode-scan button
/// that maps the result into the SKU field, photo thumbnails, and a
/// "Save & add another" secondary CTA (create mode only).
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
    /// Photos buffered locally until the item is created; up to 4 images.
    @Binding var pendingPhotos: [Data]
    let isEdit: Bool
    let errorMessage: String?
    var onScanBarcode: (() -> Void)?
    /// Called from the "Add photo" button — parent presents a picker sheet.
    var onAddPhoto: (() -> Void)?
    /// Called from "Save & add another" — only shown in create mode.
    var onSaveAndAddAnother: (() -> Void)?
    /// Called from "Manage variants" row — only active in edit mode when the
    /// item has a SKU. In create mode the row shows a read-only note instead
    /// (variants require an existing server-side item id).
    var onManageVariants: (() -> Void)?

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
            photosSection
            descriptionSection
            variantsStubSection
            if let err = errorMessage {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Error: \(err)")
            }
            if !isEdit, let onAddAnother = onSaveAndAddAnother {
                Section {
                    Button("Save & add another") {
                        onAddAnother()
                    }
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Save this item and immediately create another")
                }
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

    // MARK: - Photos section (up to 4 images)

    private var photosSection: some View {
        Section("Photos") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(Array(pendingPhotos.enumerated()), id: \.offset) { idx, data in
                        photoThumb(data: data, index: idx)
                    }
                    if pendingPhotos.count < 4, let onAdd = onAddPhoto {
                        addPhotoButton(action: onAdd)
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
        }
    }

    private func photoThumb(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Photo \(index + 1)")
            }
            Button {
                pendingPhotos.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .bizarreError)
                    .padding(4)
            }
            .accessibilityLabel("Remove photo \(index + 1)")
        }
    }

    private func addPhotoButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "camera.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.bizarreOrange)
                Text("Add")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(width: 72, height: 72)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add photo for this item")
    }

    // MARK: - Variants stub
    //
    // In create mode we have no server-side item id yet, so variant management
    // is unavailable. We show a disclosure row that explains this. In edit
    // mode the parent supplies `onManageVariants` and we render a tappable row
    // that opens VariantEditorSheet.

    private var variantsStubSection: some View {
        Section("Variants") {
            if isEdit, let manage = onManageVariants {
                Button(action: manage) {
                    HStack {
                        Label("Manage variants", systemImage: "rectangle.stack.badge.plus")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOrange)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage variant SKUs (color, size, storage…)")
                .accessibilityHint("Opens the variant editor sheet")
            } else if isEdit {
                // Edit mode but caller didn't wire the callback — show passive label.
                Label("No variants configured", systemImage: "rectangle.stack")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No variants configured for this item")
            } else {
                // Create mode: variants can only be added after the item is saved.
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Save the item first, then add variants from the detail screen.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Variants available after saving the item")
            }
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

// MARK: - Image picker UIViewControllerRepresentable

import PhotosUI

/// Lightweight UIImagePickerController bridge until the Camera package is wired.
struct InventoryImagePickerView: UIViewControllerRepresentable {
    let onImage: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void
        init(onImage: @escaping (Data) -> Void) { self.onImage = onImage }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                onImage(data)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#endif
