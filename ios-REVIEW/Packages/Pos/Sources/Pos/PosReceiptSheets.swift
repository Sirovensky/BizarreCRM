#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.7 — "Email receipt" bottom sheet. Prompts for an address when the
/// cart wasn't attached to a customer (or the customer has no email on
/// file), posts to `/notifications/send-receipt` via the view model, and
/// closes once the status flips to `.sent`.
struct PosReceiptEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: PosPostSaleViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $vm.emailInput)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pos.postSale.email.field")
                } footer: {
                    Text("The customer receives a formatted HTML receipt.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if case let .failed(message) = vm.emailStatus {
                    Section {
                        Text(message)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .accessibilityIdentifier("pos.postSale.email.error")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Email receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.dismissSheet()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .sending = vm.emailStatus {
                        ProgressView()
                    } else {
                        Button("Send") {
                            Task { await vm.submitEmail() }
                        }
                        .disabled(!vm.isEmailValid)
                        .accessibilityIdentifier("pos.postSale.email.send")
                    }
                }
            }
            .onChange(of: vm.emailStatus) { _, new in
                if case .sent = new { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// §16.7 — "Text receipt" bottom sheet. Mirrors the email sheet but posts
/// to `/sms/send` with the plain-text renderer output.
struct PosReceiptTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: PosPostSaleViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Phone number", text: $vm.phoneInput)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pos.postSale.text.field")
                } footer: {
                    Text("Sends the receipt as a plain SMS.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if case let .failed(message) = vm.smsStatus {
                    Section {
                        Text(message)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .accessibilityIdentifier("pos.postSale.text.error")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Text receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.dismissSheet()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .sending = vm.smsStatus {
                        ProgressView()
                    } else {
                        Button("Send") {
                            Task { await vm.submitSms() }
                        }
                        .disabled(!vm.isPhoneValid)
                        .accessibilityIdentifier("pos.postSale.text.send")
                    }
                }
            }
            .onChange(of: vm.smsStatus) { _, new in
                if case .sent = new { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
#endif
