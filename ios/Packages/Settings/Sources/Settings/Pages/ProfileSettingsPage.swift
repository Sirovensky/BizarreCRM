import SwiftUI
import PhotosUI
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
    /// §19.1 — read-only unless admin; comes from server `/auth/me`.
    var username: String = ""
    var isAdmin: Bool = false

    // MARK: §19.1 Avatar
    var avatarURL: String?
    var selectedAvatarItem: PhotosPickerItem?
    var avatarImage: Image?
    var showAvatarActionSheet = false
    var showPhotoPicker = false
    var isCameraSource = false

    // MARK: Password change
    var currentPassword: String = ""
    var newPassword: String = ""
    var confirmPassword: String = ""

    // MARK: §19.1 Change email
    var showChangeEmailSheet: Bool = false
    /// Non-nil when a change-email verification is pending (user submitted but hasn't clicked link yet).
    var pendingEmailChange: String? {
        get { UserDefaults.standard.string(forKey: "profile.pendingEmailChange") }
        set { UserDefaults.standard.set(newValue, forKey: "profile.pendingEmailChange") }
    }

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

    // Tracks the server-side last-loaded state to compute true dirty flag.
    private var savedFirstName: String = ""
    private var savedLastName: String = ""
    private var savedDisplayName: String = ""
    private var savedEmail: String = ""
    private var savedPhone: String = ""
    private var savedJobTitle: String = ""

    var isDirty: Bool {
        firstName != savedFirstName ||
        lastName != savedLastName ||
        displayName != savedDisplayName ||
        email != savedEmail ||
        phone != savedPhone ||
        jobTitle != savedJobTitle
    }

    let api: APIClient?

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
            // §19.1 — username/slug: read-only display from server
            username = profile.username ?? ""
            isAdmin = profile.isAdmin ?? false
            // Snapshot loaded state for dirty tracking
            savedFirstName = firstName
            savedLastName = lastName
            savedDisplayName = displayName
            savedEmail = email
            savedPhone = phone
            savedJobTitle = jobTitle
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

    func discardChanges() {
        firstName = savedFirstName
        lastName = savedLastName
        displayName = savedDisplayName
        email = savedEmail
        phone = savedPhone
        jobTitle = savedJobTitle
        errorMessage = nil
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

    // §19.1 Avatar helpers
    func loadSelectedAvatar() async {
        guard let item = selectedAvatarItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            avatarImage = Image(uiImage: uiImage)
            await uploadAvatar(data: data)
        }
    }

    private func uploadAvatar(data: Data) async {
        guard let api else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let result = try await api.settingsUploadAvatar(data: data)
            avatarURL = result.url
            successMessage = "Avatar updated."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAvatar() async {
        guard let api else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await api.settingsRemoveAvatar()
            avatarURL = nil
            avatarImage = nil
            successMessage = "Avatar removed."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // §19.1 Sign out everywhere — delegates to settingsRevokeAllSessions()
    func signOutEverywhere() async {
        guard let api else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await api.settingsRevokeAllSessions()
            successMessage = "Signed out from all devices."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct ProfileSettingsPage: View {
    @State private var vm: ProfileSettingsViewModel
    @State private var showAvatarPicker: Bool = false

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: ProfileSettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            // §19.1 Avatar — circular tap → sheet (Camera / Library / Remove)
            Section {
                HStack {
                    Spacer()
                    Button {
                        showAvatarPicker = true
                    } label: {
                        Circle()
                            .fill(Color.bizarreSurface1)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.bizarreOrange)
                                    .background(Color.bizarreSurfaceBase, in: Circle())
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change profile photo")
                    .accessibilityHint("Opens photo picker")
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

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

                // §19.1 Username / slug — read-only unless admin.
                if !vm.username.isEmpty {
                    HStack {
                        Text("Username")
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        if vm.isAdmin {
                            TextField("Username", text: $vm.username)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.bizarreOnSurface)
                                .accessibilityLabel("Username, editable (admin)")
                                .accessibilityIdentifier("profile.username")
                        } else {
                            Text(vm.username)
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .textSelection(.enabled)
                                .accessibilityLabel("Username: \(vm.username), read-only")
                                .accessibilityIdentifier("profile.username")
                        }
                    }
                }
            }

            Section("Contact") {
                // §19.1 Email — read-only display; tap "Change email" to start flow
                HStack {
                    Text(vm.email.isEmpty ? "No email set" : vm.email)
                        .font(.brandBodyMedium())
                        .foregroundStyle(vm.email.isEmpty ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                    Spacer()
                    Button("Change") {
                        vm.showChangeEmailSheet = true
                    }
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Change email address")
                    .accessibilityIdentifier("profile.changeEmail")
                }
                .accessibilityElement(children: .combine)

                // §19.1 Pending verification banner
                if let pending = vm.pendingEmailChange {
                    PendingEmailVerificationBanner(newEmail: pending) {
                        // Resend: re-show the sheet pre-filled
                        vm.showChangeEmailSheet = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                TextField("Phone", text: $vm.phone)
                    #if canImport(UIKit)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    #endif
                    .accessibilityLabel("Phone")
                    .accessibilityIdentifier("profile.phone")
            }
            .sheet(isPresented: $vm.showChangeEmailSheet) {
                if let api = vm.api {
                    ChangeEmailSheet(api: api) { success in
                        if success {
                            // Store pending state; banner appears until verify link clicked
                            vm.pendingEmailChange = vm.email   // placeholder until user types new email
                            vm.successMessage = "Verification email sent. Check your inbox."
                        }
                    }
                }
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

            // §19.1 Sign out everywhere (cross-link to §19.2 Security — revokes all other sessions)
            Section {
                Button(role: .destructive) {
                    Task { await vm.signOutEverywhere() }
                } label: {
                    Label("Sign out everywhere", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.bizarreError)
                }
                .disabled(vm.isSaving)
                .accessibilityLabel("Sign out from all devices. This revokes all active sessions.")
                .accessibilityIdentifier("profile.signOutEverywhere")
            } footer: {
                Text("Signs out this device and all other devices where you are currently logged in.")
                    .font(.brandLabelSmall())
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
        .unsavedChangesBanner(
            isDirty: vm.isDirty,
            onSave: { await vm.save() },
            onDiscard: { vm.discardChanges() }
        )
        .task { await vm.load() }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerSheet(currentAvatarUrl: nil) { _ in
                // Upload endpoint not yet available — sheet shows "coming soon" internally.
            }
        }
        .overlay {
            if vm.isLoading {
                ProgressView()
                    .accessibilityLabel("Loading profile")
            }
        }
    }
}
