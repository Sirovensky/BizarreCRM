#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Shared form body for Create + Edit. Bindings are passed in so the view
/// doesn't own the view-model — both Create and Edit drive the same layout.
struct CustomerFormView: View {
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
    @Binding var notes: String
    let errorMessage: String?

    @FocusState private var focus: Field?

    private enum Field: Hashable { case firstName, lastName, email, phone, mobile, organization, address1, city, state, postcode, notes }

    var body: some View {
        Form {
            Section("Name") {
                LabeledTextField("First name", text: $firstName, contentType: .givenName)
                    .focused($focus, equals: .firstName).submitLabel(.next).onSubmit { focus = .lastName }
                LabeledTextField("Last name", text: $lastName, contentType: .familyName)
                    .focused($focus, equals: .lastName).submitLabel(.next).onSubmit { focus = .phone }
                LabeledTextField("Organization", text: $organization, contentType: .organizationName)
            }

            Section("Contact") {
                LabeledTextField("Phone", text: $phone, contentType: .telephoneNumber, keyboard: .phonePad)
                    .focused($focus, equals: .phone).submitLabel(.next).onSubmit { focus = .mobile }
                LabeledTextField("Mobile", text: $mobile, contentType: .telephoneNumber, keyboard: .phonePad)
                    .focused($focus, equals: .mobile).submitLabel(.next).onSubmit { focus = .email }
                LabeledTextField("Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress, autocapitalize: .never)
                    .focused($focus, equals: .email)
            }

            Section("Address") {
                LabeledTextField("Street", text: $address1, contentType: .streetAddressLine1)
                LabeledTextField("City", text: $city, contentType: .addressCity)
                LabeledTextField("State", text: $state, contentType: .addressState)
                LabeledTextField("Postal code", text: $postcode, contentType: .postalCode, keyboard: .numbersAndPunctuation)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let err = errorMessage {
                Section {
                    Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }
}

/// Shared inline-label text field for customer forms.
struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var autocapitalize: TextInputAutocapitalization = .sentences

    init(_ label: String, text: Binding<String>,
         contentType: UITextContentType? = nil,
         keyboard: UIKeyboardType = .default,
         autocapitalize: TextInputAutocapitalization = .sentences) {
        self.label = label
        self._text = text
        self.contentType = contentType
        self.keyboard = keyboard
        self.autocapitalize = autocapitalize
    }

    var body: some View {
        TextField(label, text: $text)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalize)
    }
}
#endif
