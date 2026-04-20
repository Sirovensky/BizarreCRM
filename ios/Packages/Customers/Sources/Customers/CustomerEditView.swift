import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class CustomerEditViewModel {
    public let customerId: Int64

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

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
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

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
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
            didSave = true
        } catch {
            if CustomerOfflineQueue.isNetworkError(error) {
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
                errorMessage: vm.errorMessage
            )
            .navigationTitle("Edit customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                }
            }
            .overlay(alignment: .top) {
                if let banner = pendingBanner {
                    PendingSyncBanner(text: banner)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                }
            }
        }
    }
}
#endif
