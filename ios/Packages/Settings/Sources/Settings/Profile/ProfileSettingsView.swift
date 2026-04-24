import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §19.1 ProfileSettingsView

/// Full-screen profile editor.
/// iPhone: NavigationStack + Form, Liquid Glass navigation bar.
/// iPad: Two-column layout — glass avatar header on left, form on right.
public struct ProfileSettingsView: View {

    @State private var vm: ProfileSettingsViewModel
    @State private var showAvatarPicker: Bool = false

    public init(repository: (any ProfileSettingsRepository)? = nil) {
        _vm = State(initialValue: ProfileSettingsViewModel(repository: repository))
    }

    public var body: some View {
        if Platform.isCompact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        Form {
            avatarSection
            identitySection
            contactSection
            localeSection
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Profile")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar { saveToolbarItem }
        .task { await vm.load() }
        .overlay { loadingOverlay }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerSheet(currentAvatarUrl: vm.settings.avatarUrl) { _ in
                // Upload is a stub — sheet shows "coming soon" toast internally.
            }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.dismissError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("Saved", isPresented: .constant(vm.successMessage != nil)) {
            Button("OK") { vm.dismissSuccess() }
        } message: {
            Text(vm.successMessage ?? "")
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left panel — avatar + name summary with glass chrome
            VStack(spacing: DesignTokens.Spacing.lg) {
                avatarButton
                    .frame(width: 96, height: 96)
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.bizarreOnSurface)
                Text(vm.settings.email)
                    .font(.subheadline)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(width: 220)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .padding(DesignTokens.Spacing.lg)

            Divider()

            // Right panel — full form
            Form {
                identitySection
                contactSection
                localeSection
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Profile")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar { saveToolbarItem }
        .task { await vm.load() }
        .overlay { loadingOverlay }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerSheet(currentAvatarUrl: vm.settings.avatarUrl) { _ in }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.dismissError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("Saved", isPresented: .constant(vm.successMessage != nil)) {
            Button("OK") { vm.dismissSuccess() }
        } message: {
            Text(vm.successMessage ?? "")
        }
    }

    // MARK: - Sections

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                avatarButton
                    .frame(width: 72, height: 72)
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var identitySection: some View {
        Section("Identity") {
            TextField("First name", text: Binding(
                get: { vm.settings.firstName },
                set: { vm.setFirstName($0) }
            ))
            #if canImport(UIKit)
            .textContentType(.givenName)
            .autocapitalization(.words)
            #endif
            .accessibilityLabel("First name")
            .accessibilityIdentifier("profile.firstName")

            TextField("Last name", text: Binding(
                get: { vm.settings.lastName },
                set: { vm.setLastName($0) }
            ))
            #if canImport(UIKit)
            .textContentType(.familyName)
            .autocapitalization(.words)
            #endif
            .accessibilityLabel("Last name")
            .accessibilityIdentifier("profile.lastName")
        }
    }

    private var contactSection: some View {
        Section("Contact") {
            TextField("Email", text: Binding(
                get: { vm.settings.email },
                set: { vm.setEmail($0) }
            ))
            #if canImport(UIKit)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            #endif
            .accessibilityLabel("Email address")
            .accessibilityIdentifier("profile.email")

            TextField("Phone", text: Binding(
                get: { vm.settings.phone },
                set: { vm.setPhone($0) }
            ))
            #if canImport(UIKit)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            #endif
            .accessibilityLabel("Phone number")
            .accessibilityIdentifier("profile.phone")
        }
    }

    private var localeSection: some View {
        Section("Regional") {
            LabeledContent("Timezone") {
                Text(vm.settings.timezone.isEmpty ? "—" : vm.settings.timezone)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityIdentifier("profile.timezone")

            LabeledContent("Locale") {
                Text(vm.settings.locale.isEmpty ? "—" : vm.settings.locale)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityIdentifier("profile.locale")
        }
    }

    // MARK: - Shared sub-views

    @ViewBuilder
    private var avatarButton: some View {
        Button {
            showAvatarPicker = true
        } label: {
            AvatarView(
                url: vm.settings.avatarUrl,
                initials: initials
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 22))
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change profile photo")
        .accessibilityIdentifier("profile.avatarButton")
    }

    @ToolbarContentBuilder
    private var saveToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task { await vm.save() }
            }
            .disabled(vm.isSaving || !vm.isDirty)
            .accessibilityIdentifier("profile.save")
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bizarreSurfaceBase.opacity(0.4))
                .accessibilityLabel("Loading profile")
        }
    }

    // MARK: - Computed helpers

    private var displayName: String {
        let parts = [vm.settings.firstName, vm.settings.lastName].filter { !$0.isEmpty }
        return parts.isEmpty ? "Profile" : parts.joined(separator: " ")
    }

    private var initials: String {
        let first = vm.settings.firstName.first.map(String.init) ?? ""
        let last  = vm.settings.lastName.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

// MARK: - AvatarView (inline helper)

/// Circular avatar: shows remote image when URL is present, monogram otherwise.
private struct AvatarView: View {
    let url: String?
    let initials: String

    var body: some View {
        Group {
            if let rawUrl = url, let imageURL = URL(string: rawUrl) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.bizarreOutline, lineWidth: 1))
    }

    private var monogram: some View {
        ZStack {
            Circle()
                .fill(Color.bizarreOrange.opacity(0.15))
            Text(initials.isEmpty ? "?" : initials)
                .font(.title3.bold())
                .foregroundStyle(.bizarreOrange)
        }
    }
}
