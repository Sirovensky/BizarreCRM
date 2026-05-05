#if canImport(UIKit)
import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §6.2 Tax class — editable (admin only)
// Displayed when server returns a non-nil taxClass.
// Admin can edit via PATCH /api/v1/inventory/:id { tax_class }.

// MARK: - ViewModel

@MainActor
@Observable
public final class InventoryTaxClassViewModel {
    public var taxClass: String
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var showSuccess: Bool = false

    private let itemId: Int64
    @ObservationIgnored private let api: APIClient?

    public init(itemId: Int64, taxClass: String, api: APIClient?) {
        self.itemId = itemId
        self.taxClass = taxClass
        self.api = api
    }

    /// Standard tax classes matched to server enum.
    public static let availableClasses: [String] = [
        "standard",
        "reduced",
        "zero",
        "exempt",
        "luxury",
        "digital_services",
        "food",
        "medical"
    ]

    public static func displayName(_ raw: String) -> String {
        switch raw {
        case "standard":        return "Standard"
        case "reduced":         return "Reduced Rate"
        case "zero":            return "Zero Rate"
        case "exempt":          return "Exempt"
        case "luxury":          return "Luxury"
        case "digital_services": return "Digital Services"
        case "food":            return "Food / FMCG"
        case "medical":         return "Medical"
        default:                return raw.capitalized
        }
    }

    public func save() async {
        guard let api else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await api.updateInventoryTaxClass(id: itemId, taxClass: taxClass)
            showSuccess = true
            BrandHaptics.success()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSuccess = false
        } catch {
            AppLog.ui.error("TaxClass save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct InventoryTaxClassCard: View {
    @State private var vm: InventoryTaxClassViewModel
    @State private var isEditing: Bool = false

    public init(itemId: Int64, taxClass: String, api: APIClient?) {
        _vm = State(wrappedValue: InventoryTaxClassViewModel(itemId: itemId, taxClass: taxClass, api: api))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Label("Tax Class", systemImage: "percent")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !isEditing {
                    Button("Edit") { isEditing = true }
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Edit tax class")
                }
            }

            if isEditing {
                Picker("Tax class", selection: $vm.taxClass) {
                    ForEach(InventoryTaxClassViewModel.availableClasses, id: \.self) { cls in
                        Text(InventoryTaxClassViewModel.displayName(cls)).tag(cls)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .clipped()
                .accessibilityLabel("Select tax class")

                HStack(spacing: BrandSpacing.sm) {
                    Button("Cancel", role: .cancel) {
                        isEditing = false
                    }
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Cancel tax class edit")

                    Spacer()

                    Button {
                        Task { await vm.save(); isEditing = false }
                    } label: {
                        if vm.isSaving {
                            ProgressView().tint(.bizarreOrange)
                        } else {
                            Text("Save")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOrange)
                        }
                    }
                    .disabled(vm.isSaving)
                    .accessibilityLabel("Save tax class")
                }
            } else {
                HStack {
                    Text(InventoryTaxClassViewModel.displayName(vm.taxClass))
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if vm.showSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("Saved")
                    }
                }
                .animation(.spring(duration: 0.3), value: vm.showSuccess)
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }
        }
        .cardBackground()
    }
}

#endif
