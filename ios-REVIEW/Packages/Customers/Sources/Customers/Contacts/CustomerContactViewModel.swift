import Foundation
import Observation
import Core
import Networking

// §5.6 Customer contacts ViewModel — sub-contacts under a business customer.

@MainActor
@Observable
public final class CustomerContactViewModel {

    // MARK: - State

    public var contacts: [CustomerContact] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String? = nil
    public private(set) var isSaving: Bool = false
    public private(set) var savedContact: CustomerContact? = nil

    // MARK: - Edit state

    public var editingContact: CustomerContact? = nil
    public var editName: String = ""
    public var editRelationship: String = ""
    public var editPhone: String = ""
    public var editEmail: String = ""
    public var editIsPrimary: Bool = false

    public var isEditValid: Bool {
        !editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let customerId: Int64

    // MARK: - Init

    public init(api: APIClient, customerId: Int64) {
        self.api = api
        self.customerId = customerId
    }

    // MARK: - Load

    public func load() async {
        isLoading = contacts.isEmpty
        defer { isLoading = false }
        errorMessage = nil
        do {
            contacts = try await api.customerContacts(id: customerId)
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    // MARK: - Prepare edit sheet

    public func prepareNew() {
        editingContact = nil
        editName = ""
        editRelationship = ""
        editPhone = ""
        editEmail = ""
        editIsPrimary = false
        savedContact = nil
    }

    public func prepareEdit(_ contact: CustomerContact) {
        editingContact = contact
        editName = contact.name
        editRelationship = contact.relationship ?? ""
        editPhone = contact.phone ?? ""
        editEmail = contact.email ?? ""
        editIsPrimary = contact.isPrimary
        savedContact = nil
    }

    // MARK: - Save

    public func saveContact() async {
        guard isEditValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let req = UpsertCustomerContactRequest(
            name: editName.trimmingCharacters(in: .whitespaces),
            relationship: trim(editRelationship),
            phone: trim(editPhone).map { PhoneFormatter.normalize($0) },
            email: trim(editEmail),
            isPrimary: editIsPrimary
        )

        do {
            let result: CustomerContact
            if let existing = editingContact {
                result = try await api.updateCustomerContact(customerId: customerId, contactId: existing.id, req)
                contacts = contacts.map { $0.id == existing.id ? result : $0 }
            } else {
                result = try await api.createCustomerContact(customerId: customerId, req)
                contacts = contacts + [result]
            }
            savedContact = result
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    // MARK: - Delete

    public func deleteContact(_ contact: CustomerContact) async {
        do {
            try await api.deleteCustomerContact(customerId: customerId, contactId: contact.id)
            contacts = contacts.filter { $0.id != contact.id }
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    // MARK: - Helpers

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
