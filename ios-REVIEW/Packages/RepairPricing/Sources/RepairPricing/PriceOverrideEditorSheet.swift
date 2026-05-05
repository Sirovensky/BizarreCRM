import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43.3 Price Override Editor Sheet

/// Sheet overlay for creating a price override on a specific service.
/// Presented from a long-press or "Override price" button on a service row.
@MainActor
public struct PriceOverrideEditorSheet: View {
    @State private var vm: PriceOverrideEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let serviceName: String
    private let onSaved: (PriceOverride) -> Void

    public init(api: APIClient, serviceId: String, serviceName: String, onSaved: @escaping (PriceOverride) -> Void) {
        self.serviceName = serviceName
        self.onSaved = onSaved
        _vm = State(wrappedValue: PriceOverrideEditorViewModel(api: api, serviceId: serviceId))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .navigationTitle("Override Price")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("priceOverride.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView().tint(.bizarreOrange)
                    } else {
                        Button("Save") {
                            Task { await saveAndDismiss() }
                        }
                        .bold()
                        .accessibilityIdentifier("priceOverride.save")
                    }
                }
            }
            .onChange(of: vm.savedOverride) { _, new in
                guard let saved = new else { return }
                onSaved(saved)
                dismiss()
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Form

    private var form: some View {
        Form {
            // Service header
            Section {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    Text(serviceName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityLabel("Service: \(serviceName)")
            } header: {
                Text("Service")
            }
            .listRowBackground(Color.bizarreSurface1)

            // Scope picker
            Section {
                Picker("Scope", selection: $vm.scope) {
                    ForEach(OverrideScope.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Override scope")
                .accessibilityHint("Choose tenant for all customers or customer for one VIP customer")
            } header: {
                Text("Scope")
            }
            .listRowBackground(Color.bizarreSurface1)

            // Customer ID field (only when scope == .customer)
            if vm.scope == .customer {
                Section {
                    TextField("Customer ID", text: $vm.customerId)
                        #if canImport(UIKit)
                        .keyboardType(.default)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        #endif
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Customer ID")
                        .accessibilityIdentifier("priceOverride.customerId")
                } header: {
                    Text("Customer")
                } footer: {
                    Text("Enter the customer's ID to apply VIP pricing.")
                        .font(.brandLabelSmall())
                }
                .listRowBackground(Color.bizarreSurface1)
                .transition(reduceMotion ? .identity : .opacity)
            }

            // New price
            Section {
                HStack {
                    Text("$")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    TextField("0.00", text: $vm.rawPrice)
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("New price in dollars")
                        .accessibilityIdentifier("priceOverride.price")
                }
                if let msg = vm.priceValidationMessage {
                    Text(msg)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Validation error: \(msg)")
                }
            } header: {
                Text("New Price")
            }
            .listRowBackground(Color.bizarreSurface1)

            // Reason (optional)
            Section {
                TextField("Reason (optional)", text: $vm.reason, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Reason for override")
                    .accessibilityIdentifier("priceOverride.reason")
            } header: {
                Text("Reason")
            }
            .listRowBackground(Color.bizarreSurface1)

            // Error banner
            if let err = vm.saveError {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Save error: \(err)")
                }
                .listRowBackground(Color.bizarreError.opacity(0.1))
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func saveAndDismiss() async {
        await vm.save()
    }
}
