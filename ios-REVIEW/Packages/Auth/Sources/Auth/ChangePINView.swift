#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Persistence
import Core

// MARK: - ChangePINView
//
// §2.5 — Settings → Security → Change PIN.
// Uses the public ChangePINViewModel defined in ChangePIN/ChangePINViewModel.swift.

public struct ChangePINView: View {
    @State private var vm: ChangePINViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient) {
        _vm = State(wrappedValue: ChangePINViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Current PIN") {
                    SecureField("Current PIN", text: $vm.currentPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .onChange(of: vm.currentPIN) { _, v in
                            vm.currentPIN = String(v.filter(\.isNumber).prefix(6))
                        }
                        .accessibilityIdentifier("changePIN.current")
                }

                Section("New PIN") {
                    SecureField("New PIN (4–6 digits)", text: $vm.newPIN)
                        .keyboardType(.numberPad)
                        .onChange(of: vm.newPIN) { _, v in
                            vm.newPIN = String(v.filter(\.isNumber).prefix(6))
                        }
                        .accessibilityIdentifier("changePIN.new")

                    SecureField("Confirm new PIN", text: $vm.confirmPIN)
                        .keyboardType(.numberPad)
                        .onChange(of: vm.confirmPIN) { _, v in
                            vm.confirmPIN = String(v.filter(\.isNumber).prefix(6))
                        }
                        .accessibilityIdentifier("changePIN.confirm")
                }

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                    }
                }
                if let ok = vm.successMessage {
                    Section {
                        Label(ok, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                    }
                }

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isSubmitting { ProgressView() }
                            else { Text("Change PIN").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .accessibilityIdentifier("changePIN.submit")
                }
            }
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#endif
