import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - FirstEmployeeStepView  (§36 — First Employee)
//
// Creates the first employee account (beyond the owner) via
//   POST /api/v1/settings/users  (server: routes/settings.routes.ts l.863)
//
// The step is optional: leaving all fields blank skips user creation.
// Fields: first name, last name, email (required when not skipping), role.
//
// Data is surfaced to the wizard via onNext(FirstEmployeePayload?) and
// also written into wizardPayload for draft persistence.

// MARK: - ViewModel

@MainActor
@Observable
final class FirstEmployeeViewModel {

    var firstName: String = ""
    var lastName: String  = ""
    var email: String     = ""
    var role: FirstEmployeeRole = .technician

    var firstNameError: String? = nil
    var lastNameError: String?  = nil
    var emailError: String?     = nil

    var hasAnyInput: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty  ||
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Step is valid when either fully blank (skip) or fully filled-in.
    var isNextEnabled: Bool {
        if !hasAnyInput { return true }
        return validateFirstName(firstName).isValid &&
               validateLastName(lastName).isValid &&
               Step9Validator.validateEmail(email).isValid
    }

    func onFirstNameBlur() {
        guard !firstName.isEmpty else { firstNameError = nil; return }
        let r = validateFirstName(firstName)
        firstNameError = r.isValid ? nil : r.errorMessage
    }

    func onLastNameBlur() {
        guard !lastName.isEmpty else { lastNameError = nil; return }
        let r = validateLastName(lastName)
        lastNameError = r.isValid ? nil : r.errorMessage
    }

    func onEmailBlur() {
        guard !email.isEmpty else { emailError = nil; return }
        let r = Step9Validator.validateEmail(email)
        emailError = r.isValid ? nil : r.errorMessage
    }

    /// Returns nil when the user left all fields blank (skip case).
    var asPayload: FirstEmployeePayload? {
        let fn = firstName.trimmingCharacters(in: .whitespaces)
        let ln = lastName.trimmingCharacters(in: .whitespaces)
        let em = email.trimmingCharacters(in: .whitespaces)
        guard !fn.isEmpty || !ln.isEmpty || !em.isEmpty else { return nil }
        return FirstEmployeePayload(firstName: fn, lastName: ln, email: em, role: role)
    }

    // MARK: Private validators

    private func validateFirstName(_ value: String) -> ValidationResult {
        let t = value.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return .invalid("First name is required.") }
        guard t.count <= 100 else { return .invalid("First name is too long.") }
        return .valid
    }

    private func validateLastName(_ value: String) -> ValidationResult {
        let t = value.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return .invalid("Last name is required.") }
        guard t.count <= 100 else { return .invalid("Last name is too long.") }
        return .valid
    }
}

// MARK: - FirstEmployeeRole

public enum FirstEmployeeRole: String, CaseIterable, Sendable, Equatable {
    case manager    = "manager"
    case technician = "technician"
    case sales      = "sales"

    public var displayName: String {
        switch self {
        case .manager:    return "Manager"
        case .technician: return "Technician"
        case .sales:      return "Sales"
        }
    }
}

// MARK: - Payload

public struct FirstEmployeePayload: Sendable, Equatable {
    public let firstName: String
    public let lastName: String
    public let email: String
    public let role: FirstEmployeeRole

    public init(firstName: String, lastName: String, email: String, role: FirstEmployeeRole) {
        self.firstName = firstName
        self.lastName  = lastName
        self.email     = email
        self.role      = role
    }
}

// MARK: - View

public struct FirstEmployeeStepView: View {

    let onValidityChanged: (Bool) -> Void
    let onNext: (FirstEmployeePayload?) -> Void

    @State private var vm = FirstEmployeeViewModel()
    @FocusState private var focus: FocusField?

    enum FocusField: Hashable { case firstName, lastName, email }

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (FirstEmployeePayload?) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                headerSection
                firstNameField
                lastNameField
                emailField
                rolePicker
                skipHint
                Spacer(minLength: BrandSpacing.xxl)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.lg)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
        .onAppear {
            onValidityChanged(vm.isNextEnabled)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("First Employee")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text("Add your first team member. Leave blank to skip — you can add more from Employees later.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - First Name

    private var firstNameField: some View {
        fieldStack(label: "First Name", hint: "Required", error: vm.firstNameError) {
            TextField("First name", text: $vm.firstName)
                .font(.brandBodyLarge())
                .focused($focus, equals: .firstName)
                .submitLabel(.next)
                .onSubmit { focus = .lastName }
                .onChange(of: focus) { old, new in
                    if old == .firstName && new != .firstName { vm.onFirstNameBlur() }
                }
                #if canImport(UIKit)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                #endif
                .accessibilityLabel("Employee first name")
        }
    }

    // MARK: - Last Name

    private var lastNameField: some View {
        fieldStack(label: "Last Name", hint: "Required", error: vm.lastNameError) {
            TextField("Last name", text: $vm.lastName)
                .font(.brandBodyLarge())
                .focused($focus, equals: .lastName)
                .submitLabel(.next)
                .onSubmit { focus = .email }
                .onChange(of: focus) { old, new in
                    if old == .lastName && new != .lastName { vm.onLastNameBlur() }
                }
                #if canImport(UIKit)
                .textContentType(.familyName)
                .autocorrectionDisabled()
                #endif
                .accessibilityLabel("Employee last name")
        }
    }

    // MARK: - Email

    private var emailField: some View {
        fieldStack(label: "Email", hint: "Required — employee@example.com", error: vm.emailError) {
            TextField("Email address", text: $vm.email)
                .font(.brandBodyLarge())
                .focused($focus, equals: .email)
                .submitLabel(.done)
                .onSubmit {
                    focus = nil
                    if vm.isNextEnabled { onNext(vm.asPayload) }
                }
                .onChange(of: focus) { old, new in
                    if old == .email && new != .email { vm.onEmailBlur() }
                }
                #if canImport(UIKit)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel("Employee email address")
                .accessibilityHint("employee@example.com")
        }
    }

    // MARK: - Role picker

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Role")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Picker("Role", selection: $vm.role) {
                ForEach(FirstEmployeeRole.allCases, id: \.self) { r in
                    Text(r.displayName).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Employee role")
            .accessibilityValue(vm.role.displayName)
        }
    }

    // MARK: - Skip hint

    private var skipHint: some View {
        Text("Leave all fields blank to skip this step.")
            .font(.brandBodyMedium())
            .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.65))
    }

    // MARK: - Field builder

    @ViewBuilder
    private func fieldStack<Content: View>(
        label: String,
        hint: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            content()
                .padding(BrandSpacing.md)
                .background(
                    Color.bizarreSurface1.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            error != nil ? Color.bizarreError : Color.bizarreOutline.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .accessibilityHint(hint)

            if let error {
                Text(error)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
                    .accessibilityLabel("Error: \(error)")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: error)
    }
}
