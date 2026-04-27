import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class ProfileSettingsViewModel: Sendable {

    // MARK: Fields
    var firstName: String = ""
    var lastName: String = ""
    var displayName: String = ""
    var email: String = ""
    var phone: String = ""
    var jobTitle: String = ""

    // MARK: Password change
    var currentPassword: String = ""
    var newPassword: String = ""
    var confirmPassword: String = ""

    // MARK: State
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?
    var showPasswordSection: Bool = false

    // MARK: Validation
    var passwordStrength: Int {
        let p = newPassword
        var score = 0
        if p.count >= 8 { score += 1 }
        if p.contains(where: \.isUppercase) { score += 1 }
        if p.contains(where: \.isNumber) { score += 1 }
        if p.contains(where: { "!@#$%^&*".contains($0) }) { score += 1 }
        return score
    }

    var passwordsMatch: Bool { newPassword == confirmPassword && !newPassword.isEmpty }
    var isDirty: Bool {
        !firstName.isEmpty || !lastName.isEmpty || !displayName.isEmpty
    }

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let api else { return }
        do {
            let profile = try await api.fetchUserProfile()
            firstName = profile.firstName ?? ""
            lastName = profile.lastName ?? ""
            displayName = profile.displayName ?? ""
            email = profile.email ?? ""
            phone = profile.phone ?? ""
            jobTitle = profile.jobTitle ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = UserProfileUpdateDTO(
                firstName: firstName,
                lastName: lastName,
                displayName: displayName,
                email: email,
                phone: phone,
                jobTitle: jobTitle
            )
            _ = try await api.updateUserProfile(body)
            successMessage = "Profile saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func changePassword() async {
        guard passwordsMatch else {
            errorMessage = "Passwords do not match."
            return
        }
        isSaving = true
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = ChangePasswordDTO(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            try await api.changePassword(body)
            successMessage = "Password updated."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            showPasswordSection = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct ProfileSettingsPage: View {
    @State private var vm: ProfileSettingsViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: ProfileSettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Identity") {
                TextField("First name", text: $vm.firstName)
                    #if canImport(UIKit)
                    .textContentType(.givenName)
                    #endif
                    .accessibilityLabel("First name")
                    .accessibilityIdentifier("profile.firstName")
                TextField("Last name", text: $vm.lastName)
                    #if canImport(UIKit)
                    .textContentType(.familyName)
                    #endif
                    .accessibilityLabel("Last name")
                    .accessibilityIdentifier("profile.lastName")
                TextField("Display name", text: $vm.displayName)
                    .accessibilityLabel("Display name")
                    .accessibilityIdentifier("profile.displayName")
                TextField("Job title", text: $vm.jobTitle)
                    .accessibilityLabel("Job title")
                    .accessibilityIdentifier("profile.jobTitle")
            }

            Section("Contact") {
                TextField("Email", text: $vm.email)
                    #if canImport(UIKit)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("Email")
                    .accessibilityIdentifier("profile.email")
                TextField("Phone", text: $vm.phone)
                    #if canImport(UIKit)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    #endif
                    .accessibilityLabel("Phone")
                    .accessibilityIdentifier("profile.phone")
            }

            Section {
                Button(vm.showPasswordSection ? "Cancel password change" : "Change password") {
                    vm.showPasswordSection.toggle()
                }
                .accessibilityIdentifier("profile.changePasswordToggle")
            }

            if vm.showPasswordSection {
                Section("Change password") {
                    SecureField("Current password", text: $vm.currentPassword)
                        #if canImport(UIKit)
                        .textContentType(.password)
                        #endif
                        .accessibilityLabel("Current password")
                        .accessibilityIdentifier("profile.currentPassword")
                    SecureField("New password", text: $vm.newPassword)
                        #if canImport(UIKit)
                        .textContentType(.newPassword)
                        #endif
                        .accessibilityLabel("New password")
                        .accessibilityIdentifier("profile.newPassword")
                    SecureField("Confirm new password", text: $vm.confirmPassword)
                        #if canImport(UIKit)
                        .textContentType(.newPassword)
                        #endif
                        .accessibilityLabel("Confirm new password")
                        .accessibilityIdentifier("profile.confirmPassword")

                    HStack(spacing: BrandSpacing.xs) {
                        ForEach(0..<4) { i in
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(i < vm.passwordStrength ? Color.bizarreSuccess : Color.bizarreOutline)
                                .frame(height: 4)
                                .animation(.easeInOut, value: vm.passwordStrength)
                        }
                    }
                    .accessibilityLabel("Password strength: \(vm.passwordStrength) of 4")

                    Button("Update password") {
                        Task { await vm.changePassword() }
                    }
                    .disabled(!vm.passwordsMatch || vm.isSaving)
                    .accessibilityIdentifier("profile.submitPassword")
                }
            }

            if let msg = vm.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(msg)")
                }
            }

            if let msg = vm.successMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel("Success: \(msg)")
                }
            }
        }
        .navigationTitle("Profile")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("profile.save")
            }
        }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading {
                ProgressView()
                    .accessibilityLabel("Loading profile")
            }
        }
    }
}
