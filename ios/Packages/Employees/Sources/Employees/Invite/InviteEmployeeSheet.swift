import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - InviteEmployeeSheet
//
// §14.4 Invite — `POST /api/v1/settings/users` with `{ username, first_name, last_name, email?, role }`.
// Admin creates a new employee account. Email is optional because self-hosted
// servers may not have SMTP configured; in that case admin shares credentials manually.
// Presented as a sheet from EmployeeListView.

@MainActor
@Observable
public final class InviteEmployeeViewModel {

    // MARK: - Form fields
    public var firstName: String = ""
    public var lastName: String = ""
    public var username: String = ""
    public var email: String = ""
    public var role: String = "technician"
    public var password: String = ""
    public var showPasswordField: Bool = false

    // MARK: - State
    public private(set) var isSubmitting: Bool = false
    public private(set) var submitError: String?
    public private(set) var createdEmployee: Employee?

    // MARK: - Available roles
    public let availableRoles: [String] = [
        "technician", "cashier", "manager", "admin"
    ]

    // MARK: - Validation

    public var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        (password.isEmpty || password.count >= 8)
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Auto-derive username

    public func deriveUsername() {
        guard username.isEmpty else { return }
        let f = firstName.lowercased().filter { $0.isLetter }
        let l = lastName.lowercased().filter { $0.isLetter }
        username = f + l
    }

    // MARK: - Submit

    public func submit() async {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        let body = CreateEmployeeBody(
            username: username.trimmingCharacters(in: .whitespaces),
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
            role: role,
            password: password.isEmpty ? nil : password
        )
        do {
            createdEmployee = try await api.inviteEmployee(body)
        } catch {
            AppLog.ui.error("InviteEmployee failed: \(error.localizedDescription, privacy: .public)")
            submitError = error.localizedDescription
        }
    }
}

// MARK: - View

public struct InviteEmployeeSheet: View {
    @State private var vm: InviteEmployeeViewModel
    @Environment(\.dismiss) private var dismiss
    private let onCreated: (Employee) -> Void

    public init(api: APIClient, onCreated: @escaping (Employee) -> Void) {
        _vm = State(wrappedValue: InviteEmployeeViewModel(api: api))
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                nameSection
                credentialsSection
                roleSection
                if let err = vm.submitError {
                    Section {
                        Label(err, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                            .accessibilityLabel("Error: \(err)")
                    }
                }
            }
            .navigationTitle("Invite Employee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .disabled(vm.isSubmitting)
            .onChange(of: vm.createdEmployee) { _, emp in
                if let emp {
                    onCreated(emp)
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("First name", text: $vm.firstName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityLabel("First name")
                .onChange(of: vm.firstName) { _, _ in vm.deriveUsername() }
            TextField("Last name", text: $vm.lastName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityLabel("Last name")
                .onChange(of: vm.lastName) { _, _ in vm.deriveUsername() }
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField("Username (required)", text: $vm.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Username (required)")
            TextField("Email (optional)", text: $vm.email)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Email address (optional)")
            Toggle("Set initial password", isOn: $vm.showPasswordField)
                .accessibilityLabel("Toggle initial password field")
            if vm.showPasswordField {
                SecureField("Password (min 8 characters)", text: $vm.password)
                    .accessibilityLabel("Initial password")
            }
        } header: {
            Text("Login Credentials")
        } footer: {
            if vm.email.isEmpty {
                Text("No email address — share login credentials with the employee manually after creation.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private var roleSection: some View {
        Section("Role") {
            Picker("Role", selection: $vm.role) {
                ForEach(vm.availableRoles, id: \.self) { role in
                    Text(role.capitalized).tag(role)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Select role")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel invite")
        }
        ToolbarItem(placement: .primaryAction) {
            if vm.isSubmitting {
                ProgressView()
            } else {
                Button("Create") {
                    Task { await vm.submit() }
                }
                .disabled(!vm.isValid)
                .fontWeight(.semibold)
                .accessibilityLabel("Create employee account")
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}
