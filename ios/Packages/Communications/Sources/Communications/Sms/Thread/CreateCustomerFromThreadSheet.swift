import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CreateCustomerFromThreadSheet
//
// §12.2 Create customer from thread — shown when the thread's phone number is
// not yet associated with a customer. Allows staff to create a new customer
// record with the phone pre-filled.
//
// Architecture:
//   CreateCustomerFromThreadSheet  — sheet UI
//   CreateCustomerFromThreadViewModel — @Observable, calls POST /api/v1/customers
//
// Usage:
//   .sheet(isPresented: $showCreateCustomer) {
//       CreateCustomerFromThreadSheet(phoneNumber: thread.rawPhone, api: api) { newId in ... }
//   }

public struct CreateCustomerFromThreadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CreateCustomerFromThreadViewModel

    private let onCreated: (Int64) -> Void

    public init(phoneNumber: String, api: APIClient, onCreated: @escaping (Int64) -> Void) {
        _vm = State(wrappedValue: CreateCustomerFromThreadViewModel(phoneNumber: phoneNumber, api: api))
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        phoneRow
                        Divider().overlay(Color.bizarreOutline.opacity(0.4))
                        nameFields
                        emailField
                        if let err = vm.errorMessage {
                            Text(err)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreError)
                                .padding(.horizontal, BrandSpacing.base)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.lg)
                }
            }
            .navigationTitle("New Customer")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { toolbarItems }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Fields

    private var phoneRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Phone (pre-filled from thread)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(vm.phoneNumber)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Phone number: \(vm.phoneNumber)")
    }

    private var nameFields: some View {
        HStack(spacing: BrandSpacing.md) {
            brandField("First name", text: $vm.firstName, identifier: "create.customer.firstName")
            brandField("Last name", text: $vm.lastName, identifier: "create.customer.lastName")
        }
    }

    private var emailField: some View {
        brandField("Email (optional)", text: $vm.email, identifier: "create.customer.email")
#if !os(macOS)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .autocapitalization(.none)
#endif
    }

    private func brandField(_ label: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .frame(minHeight: 44)
                .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                .accessibilityIdentifier(identifier)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("create.customer.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task {
                    if let newId = await vm.createCustomer() {
                        onCreated(newId)
                        dismiss()
                    }
                }
            } label: {
                if vm.isSaving {
                    ProgressView().tint(.bizarreOrange)
                } else {
                    Text("Save")
                        .font(.brandBodyMedium().weight(.semibold))
                }
            }
            .disabled(!vm.isValid || vm.isSaving)
            .accessibilityIdentifier("create.customer.save")
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class CreateCustomerFromThreadViewModel {
    public let phoneNumber: String
    public var firstName: String = ""
    public var lastName: String = ""
    public var email: String = ""
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(phoneNumber: String, api: APIClient) {
        self.phoneNumber = phoneNumber
        self.api = api
    }

    public var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Creates the customer and returns the new customer ID, or nil on error.
    public func createCustomer() async -> Int64? {
        guard isValid, !isSaving else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let result = try await api.createCustomerFromThread(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                phone: phoneNumber,
                email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces)
            )
            return result
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("Create customer from thread failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
