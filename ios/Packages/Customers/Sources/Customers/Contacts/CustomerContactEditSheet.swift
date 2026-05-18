#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// §5.6 — Add/edit a sub-contact sheet.

struct CustomerContactEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: CustomerContactViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Full name", text: $vm.editName)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Contact full name")
                    TextField("Relationship (e.g. Spouse, Manager)", text: $vm.editRelationship)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Contact relationship")
                }
                // BUGHUNT-2026-05-18: textContentType was missing — keyboard
                // type was right but iOS Autofill suggestions weren't offered.
                // For a sub-contact (e.g. account holder's spouse), the user
                // usually wants to pull from Contacts.
                Section("Contact details") {
                    TextField("Phone", text: $vm.editPhone)
                        #if canImport(UIKit)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        #endif
                        .accessibilityLabel("Contact phone")
                    TextField("Email", text: $vm.editEmail)
                        #if canImport(UIKit)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        #endif
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Contact email")
                }
                Section {
                    Toggle("Primary contact", isOn: $vm.editIsPrimary)
                        .accessibilityLabel("Set as primary contact")
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }
            .navigationTitle(vm.editingContact == nil ? "Add contact" : "Edit contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task {
                            await vm.saveContact()
                            if vm.savedContact != nil { dismiss() }
                        }
                    }
                    .disabled(!vm.isEditValid || vm.isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
