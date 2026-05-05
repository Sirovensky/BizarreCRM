#if canImport(UIKit)
import SwiftUI
import Contacts
import ContactsUI
import Core
import DesignSystem

// MARK: - §5.3 Import from Contacts — CNContactPickerViewController prefills create form

/// A toolbar-accessible button that presents the system contact picker.
/// On selection the picked contact's fields are mapped into the create/edit form.
public struct ImportFromContactsButton: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var email: String
    @Binding var phone: String
    @Binding var mobile: String
    @Binding var organization: String
    @Binding var address1: String
    @Binding var city: String
    @Binding var state: String
    @Binding var postcode: String

    @State private var showingPicker = false

    public init(
        firstName: Binding<String>,
        lastName: Binding<String>,
        email: Binding<String>,
        phone: Binding<String>,
        mobile: Binding<String>,
        organization: Binding<String>,
        address1: Binding<String>,
        city: Binding<String>,
        state: Binding<String>,
        postcode: Binding<String>
    ) {
        _firstName = firstName
        _lastName = lastName
        _email = email
        _phone = phone
        _mobile = mobile
        _organization = organization
        _address1 = address1
        _city = city
        _state = state
        _postcode = postcode
    }

    public var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
        }
        .accessibilityLabel("Import customer details from iOS Contacts")
        .sheet(isPresented: $showingPicker) {
            ContactPickerRepresentable { contact in
                prefill(from: contact)
            }
            .ignoresSafeArea()
        }
    }

    private func prefill(from contact: CNContact) {
        firstName = contact.givenName
        lastName = contact.familyName

        if !contact.organizationName.isEmpty {
            organization = contact.organizationName
        }

        // Phones: first mobile → mobile, first other → phone
        for labeled in contact.phoneNumbers {
            let digits = labeled.value.stringValue
            let label = labeled.label ?? ""
            if label == CNLabelPhoneNumberMobile || label.contains("mobile") || label.contains("cell") {
                if mobile.isEmpty { mobile = PhoneFormatter.normalize(digits) }
            } else {
                if phone.isEmpty { phone = PhoneFormatter.normalize(digits) }
            }
        }

        // Emails: first entry → email
        if let firstEmail = contact.emailAddresses.first?.value as String? {
            email = firstEmail
        }

        // Address: first postal address
        if let addr = contact.postalAddresses.first?.value {
            let street = [addr.street, addr.subLocality].filter { !$0.isEmpty }.joined(separator: " ")
            address1 = street
            city = addr.city
            state = addr.state
            postcode = addr.postalCode
        }
    }
}

// MARK: - UIViewControllerRepresentable wrapper for CNContactPickerViewController

private struct ContactPickerRepresentable: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        // Request the fields we need to prefill
        vc.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey
        ]
        return vc
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        init(onSelect: @escaping (CNContact) -> Void) { self.onSelect = onSelect }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}

#endif
