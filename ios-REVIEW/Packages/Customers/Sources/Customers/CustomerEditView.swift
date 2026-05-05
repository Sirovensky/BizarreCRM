import Foundation
import Observation
import Core
import Networking

// MARK: - Custom field editor model

/// A single editable custom field row for the edit form.
public struct EditableCustomField: Identifiable, Sendable {
    public let id: Int64          // definition_id
    public let name: String
    public let fieldType: String  // text | number | boolean | date | select | multiselect | textarea
    public let options: [String]
    public var value: String

    public init(id: Int64, name: String, fieldType: String, options: [String], value: String) {
        self.id = id
        self.name = name
        self.fieldType = fieldType
        self.options = options
        self.value = value
    }
}

// MARK: - CustomerEditViewModel

@MainActor
@Observable
public final class CustomerEditViewModel {
    public let customerId: Int64

    // Core fields
    public var firstName: String
    public var lastName: String
    public var email: String
    public var phone: String
    public var mobile: String
    public var organization: String
    public var address1: String
    public var city: String
    public var state: String
    public var postcode: String
    public var notes: String

    // Custom fields
    public var customFields: [EditableCustomField] = []
    public private(set) var isLoadingCustomFields: Bool = false

    // State
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var conflictMessage: String?   // §5.4 — 409 concurrent-edit banner
    public private(set) var didSave: Bool = false
    public private(set) var queuedOffline: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient, customer: CustomerDetail) {
        self.api = api
        self.customerId = customer.id
        self.firstName = customer.firstName ?? ""
        self.lastName = customer.lastName ?? ""
        self.email = customer.email ?? ""
        self.phone = customer.phone ?? ""
        self.mobile = customer.mobile ?? ""
        self.organization = customer.organization ?? ""
        self.address1 = customer.address1 ?? ""
        self.city = customer.city ?? ""
        self.state = customer.state ?? ""
        self.postcode = customer.postcode ?? ""
        self.notes = customer.comments ?? ""
    }

    public var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: — Custom field loading

    /// Loads definitions for `customer` entity type and merges any saved values.
    public func loadCustomFields() async {
        guard customFields.isEmpty else { return }
        isLoadingCustomFields = true
        defer { isLoadingCustomFields = false }

        do {
            async let defs = api.customFieldDefinitions(entityType: "customer")
            async let vals = api.customFieldValues(entityType: "customer", entityId: customerId)

            let (definitions, values) = try await (defs, vals)

            let valueMap: [Int64: String] = values.reduce(into: [:]) { map, v in
                map[v.definitionId] = v.value
            }

            customFields = definitions.map { def in
                EditableCustomField(
                    id: def.id,
                    name: def.fieldName,
                    fieldType: def.fieldType,
                    options: def.options,
                    value: valueMap[def.id] ?? ""
                )
            }
        } catch {
            // Non-fatal: custom fields are optional enrichment.
            AppLog.ui.error("Custom field load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mutates a custom field value by definition id.
    public func setCustomFieldValue(_ value: String, forId id: Int64) {
        guard let index = customFields.firstIndex(where: { $0.id == id }) else { return }
        let old = customFields[index]
        customFields[index] = EditableCustomField(
            id: old.id,
            name: old.name,
            fieldType: old.fieldType,
            options: old.options,
            value: value
        )
    }

    // MARK: — Submit

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        conflictMessage = nil
        didSave = false
        queuedOffline = false

        guard isValid else {
            errorMessage = "First name is required."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let req = buildRequest()

        do {
            _ = try await api.updateCustomer(id: customerId, req)
            // Save custom fields in parallel only when online (no queue for values yet).
            if !customFields.isEmpty {
                try await saveCustomFields()
            }
            didSave = true
        } catch {
            // 409 Conflict = concurrent edit or system-protected record.
            if let transport = error as? APITransportError,
               case .httpStatus(409, let msg) = transport {
                conflictMessage = msg ?? "This record was updated by someone else. Reload and try again."
            } else if CustomerOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Customer update failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func buildRequest() -> UpdateCustomerRequest {
        UpdateCustomerRequest(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: trim(lastName),
            email: trim(email),
            phone: trim(phone).map { PhoneFormatter.normalize($0) },
            mobile: trim(mobile).map { PhoneFormatter.normalize($0) },
            organization: trim(organization),
            address1: trim(address1),
            city: trim(city),
            state: trim(state),
            postcode: trim(postcode),
            notes: trim(notes)
        )
    }

    private func saveCustomFields() async throws {
        let entries = customFields.map {
            SetCustomFieldValuesRequest.FieldEntry(definitionId: $0.id, value: $0.value)
        }
        _ = try await api.setCustomFieldValues(
            entityType: "customer",
            entityId: customerId,
            fields: entries
        )
    }

    private func enqueueOffline(_ req: UpdateCustomerRequest) async {
        do {
            let payload = try CustomerOfflineQueue.encode(req)
            await CustomerOfflineQueue.enqueue(
                op: "update",
                entityServerId: customerId,
                payload: payload
            )
            didSave = true
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Customer update encode failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - CustomerEditView

#if canImport(UIKit)
import SwiftUI
import DesignSystem

public struct CustomerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerEditViewModel
    @State private var pendingBanner: String?
    private let onSaved: () -> Void

    public init(api: APIClient, customer: CustomerDetail, onSaved: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: CustomerEditViewModel(api: api, customer: customer))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    iPhoneLayout
                } else {
                    iPadLayout
                }
            }
            .navigationTitle("Edit customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel editing customer")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            guard vm.didSave else { return }
                            onSaved()
                            if vm.queuedOffline {
                                pendingBanner = "Saved — will sync when online"
                                try? await Task.sleep(nanoseconds: 900_000_000)
                            }
                            dismiss()
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(vm.isSubmitting ? "Saving" : "Save customer")
                }
            }
            .task { await vm.loadCustomFields() }
        }
    }

    // MARK: — iPhone layout

    private var iPhoneLayout: some View {
        CustomerFormView(
            firstName: $vm.firstName,
            lastName: $vm.lastName,
            email: $vm.email,
            phone: $vm.phone,
            mobile: $vm.mobile,
            organization: $vm.organization,
            address1: $vm.address1,
            city: $vm.city,
            state: $vm.state,
            postcode: $vm.postcode,
            notes: $vm.notes,
            customFields: $vm.customFields,
            onCustomFieldChange: { id, val in vm.setCustomFieldValue(val, forId: id) },
            isLoadingCustomFields: vm.isLoadingCustomFields,
            conflictMessage: vm.conflictMessage,
            errorMessage: vm.errorMessage
        )
        .overlay(alignment: .top) {
            if let banner = pendingBanner {
                PendingSyncBanner(text: banner)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
            }
        }
    }

    // MARK: — iPad layout (side-by-side sections)

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: core fields
            ScrollView {
                VStack(spacing: 0) {
                    CustomerFormCoreSection(
                        firstName: $vm.firstName,
                        lastName: $vm.lastName,
                        email: $vm.email,
                        phone: $vm.phone,
                        mobile: $vm.mobile,
                        organization: $vm.organization,
                        address1: $vm.address1,
                        city: $vm.city,
                        state: $vm.state,
                        postcode: $vm.postcode,
                        notes: $vm.notes,
                        conflictMessage: vm.conflictMessage,
                        errorMessage: vm.errorMessage
                    )
                    .padding(BrandSpacing.base)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right: custom fields
            ScrollView {
                CustomerFormCustomFieldsSection(
                    customFields: $vm.customFields,
                    isLoading: vm.isLoadingCustomFields,
                    onChange: { id, val in vm.setCustomFieldValue(val, forId: id) }
                )
                .padding(BrandSpacing.base)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let banner = pendingBanner {
                PendingSyncBanner(text: banner)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
            }
        }
    }
}
#endif
