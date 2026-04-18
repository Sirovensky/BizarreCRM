import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class CustomerCreateViewModel {
    public var firstName: String = ""
    public var lastName: String = ""
    public var email: String = ""
    public var phone: String = ""
    public var mobile: String = ""
    public var organization: String = ""
    public var address1: String = ""
    public var city: String = ""
    public var state: String = ""
    public var postcode: String = ""
    public var notes: String = ""

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        guard isValid else {
            errorMessage = "First name is required."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let req = CreateCustomerRequest(
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

        do {
            let created = try await api.createCustomer(req)
            createdId = created.id
        } catch {
            AppLog.ui.error("Customer create failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public struct CustomerCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerCreateViewModel
    @FocusState private var focus: Field?

    private enum Field: Hashable { case firstName, lastName, email, phone, mobile, organization, address1, city, state, postcode, notes }

    public init(api: APIClient) { _vm = State(wrappedValue: CustomerCreateViewModel(api: api)) }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    LabeledTextField("First name", text: $vm.firstName, contentType: .givenName)
                        .focused($focus, equals: .firstName).submitLabel(.next).onSubmit { focus = .lastName }
                    LabeledTextField("Last name", text: $vm.lastName, contentType: .familyName)
                        .focused($focus, equals: .lastName).submitLabel(.next).onSubmit { focus = .phone }
                    LabeledTextField("Organization", text: $vm.organization, contentType: .organizationName)
                }

                Section("Contact") {
                    LabeledTextField("Phone", text: $vm.phone, contentType: .telephoneNumber, keyboard: .phonePad)
                        .focused($focus, equals: .phone).submitLabel(.next).onSubmit { focus = .mobile }
                    LabeledTextField("Mobile", text: $vm.mobile, contentType: .telephoneNumber, keyboard: .phonePad)
                        .focused($focus, equals: .mobile).submitLabel(.next).onSubmit { focus = .email }
                    LabeledTextField("Email", text: $vm.email, contentType: .emailAddress, keyboard: .emailAddress, autocapitalize: .never)
                        .focused($focus, equals: .email)
                }

                Section("Address") {
                    LabeledTextField("Street", text: $vm.address1, contentType: .streetAddressLine1)
                    LabeledTextField("City", text: $vm.city, contentType: .addressCity)
                    LabeledTextField("State", text: $vm.state, contentType: .addressState)
                    LabeledTextField("Postal code", text: $vm.postcode, contentType: .postalCode, keyboard: .numbersAndPunctuation)
                }

                Section("Notes") {
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.createdId != nil { dismiss() }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
        }
    }
}

/// Shared inline-label text field for create forms.
private struct LabeledTextField: View {
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
