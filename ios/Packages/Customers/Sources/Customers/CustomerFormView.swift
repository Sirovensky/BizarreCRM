#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CustomerFormView (iPhone full form + Create flow)

/// Shared form body for Create + Edit on iPhone.
/// Bindings are passed in so the view doesn't own the view-model — both
/// Create and Edit drive the same layout.
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
    @Binding var customFields: [EditableCustomField]
    let onCustomFieldChange: (Int64, String) -> Void
    let isLoadingCustomFields: Bool
    let conflictMessage: String?
    let errorMessage: String?

    var body: some View {
        Form {
            CustomerFormCoreSection(
                firstName: $firstName,
                lastName: $lastName,
                email: $email,
                phone: $phone,
                mobile: $mobile,
                organization: $organization,
                address1: $address1,
                city: $city,
                state: $state,
                postcode: $postcode,
                notes: $notes,
                conflictMessage: conflictMessage,
                errorMessage: errorMessage
            )

            CustomerFormCustomFieldsSection(
                customFields: $customFields,
                isLoading: isLoadingCustomFields,
                onChange: onCustomFieldChange
            )
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }
}

// MARK: - Core fields section

/// Name / contact / address / notes + banners.
/// Used both in the iPhone Form and the iPad side-by-side layout.
struct CustomerFormCoreSection: View {
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
    let conflictMessage: String?
    let errorMessage: String?

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case firstName, lastName, email, phone, mobile, organization
        case address1, city, state, postcode, notes
    }

    var body: some View {
        Group {
            Section("Name") {
                LabeledTextField("First name", text: $firstName, contentType: .givenName)
                    .focused($focus, equals: .firstName).submitLabel(.next).onSubmit { focus = .lastName }
                    .accessibilityLabel("First name")
                LabeledTextField("Last name", text: $lastName, contentType: .familyName)
                    .focused($focus, equals: .lastName).submitLabel(.next).onSubmit { focus = .phone }
                    .accessibilityLabel("Last name")
                LabeledTextField("Organization", text: $organization, contentType: .organizationName)
                    .accessibilityLabel("Organization")
            }

            Section("Contact") {
                LabeledTextField("Phone", text: $phone, contentType: .telephoneNumber, keyboard: .phonePad)
                    .focused($focus, equals: .phone).submitLabel(.next).onSubmit { focus = .mobile }
                    .accessibilityLabel("Phone number")
                LabeledTextField("Mobile", text: $mobile, contentType: .telephoneNumber, keyboard: .phonePad)
                    .focused($focus, equals: .mobile).submitLabel(.next).onSubmit { focus = .email }
                    .accessibilityLabel("Mobile number")
                LabeledTextField("Email", text: $email, contentType: .emailAddress,
                                 keyboard: .emailAddress, autocapitalize: .never)
                    .focused($focus, equals: .email)
                    .accessibilityLabel("Email address")
            }

            Section("Address") {
                LabeledTextField("Street", text: $address1, contentType: .streetAddressLine1)
                    .accessibilityLabel("Street address")
                LabeledTextField("City", text: $city, contentType: .addressCity)
                    .accessibilityLabel("City")
                LabeledTextField("State", text: $state, contentType: .addressState)
                    .accessibilityLabel("State")
                LabeledTextField("Postal code", text: $postcode, contentType: .postalCode,
                                 keyboard: .numbersAndPunctuation)
                    .accessibilityLabel("Postal code")
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityLabel("Notes")
            }

            if let conflict = conflictMessage {
                Section {
                    conflictBanner(conflict)
                }
            }

            if let err = errorMessage {
                Section {
                    Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
    }

    private func conflictBanner(_ msg: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Conflict").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conflict: \(msg)")
    }
}

// MARK: - Custom fields section

/// Renders tenant-defined custom fields. Supports text, number, textarea,
/// boolean (toggle), select (picker), and date (DatePicker via text).
struct CustomerFormCustomFieldsSection: View {
    @Binding var customFields: [EditableCustomField]
    let isLoading: Bool
    let onChange: (Int64, String) -> Void

    var body: some View {
        if isLoading {
            Section("Custom fields") {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading custom fields")
            }
        } else if !customFields.isEmpty {
            Section("Custom fields") {
                ForEach($customFields) { $field in
                    CustomFieldRow(field: $field, onChange: onChange)
                }
            }
        }
        // When not loading and no fields — render nothing (tenant has no customer custom fields).
    }
}

// MARK: - Single custom field row

/// Renders a single custom field according to its `fieldType`.
private struct CustomFieldRow: View {
    @Binding var field: EditableCustomField
    let onChange: (Int64, String) -> Void

    var body: some View {
        switch field.fieldType {
        case "boolean":
            Toggle(field.name, isOn: boolBinding)
                .accessibilityLabel(field.name)

        case "select":
            Picker(field.name, selection: $field.value) {
                Text("—").tag("")
                ForEach(field.options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel(field.name)
            .onChange(of: field.value) { _, new in onChange(field.id, new) }

        case "number":
            LabeledTextField(field.name, text: $field.value, keyboard: .decimalPad)
                .accessibilityLabel(field.name)
                .onChange(of: field.value) { _, new in onChange(field.id, new) }

        case "textarea":
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(field.name)
                    .font(.brandLabelMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField(field.name, text: $field.value, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityLabel(field.name)
                    .onChange(of: field.value) { _, new in onChange(field.id, new) }
            }

        default:
            // text, date (stored as string), multiselect (stored as comma-separated).
            LabeledTextField(field.name, text: $field.value)
                .accessibilityLabel(field.name)
                .onChange(of: field.value) { _, new in onChange(field.id, new) }
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { field.value == "true" || field.value == "1" },
            set: { newVal in
                field.value = newVal ? "true" : "false"
                onChange(field.id, field.value)
            }
        )
    }
}

// MARK: - LabeledTextField

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
