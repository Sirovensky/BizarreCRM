import SwiftUI
import DesignSystem
import Core

// MARK: - ImpersonateUserSheet

/// Sheet for admins to impersonate another user.
/// Requires: user selection, reason field, manager PIN, audit-log consent.
public struct ImpersonateUserSheet: View {

    @Environment(\.dismiss) private var dismiss

    /// Available users the admin can impersonate (provided by caller).
    let users: [UserRow]
    let onConfirm: (String, String, String) async -> Bool

    // MARK: Local state

    @State private var selectedUserId: String = ""
    @State private var reason: String = ""
    @State private var managerPin: String = ""
    @State private var consentChecked: Bool = false
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    @State private var showPINField: Bool = false

    @FocusState private var focused: FocusedField?

    public init(
        users: [UserRow],
        onConfirm: @escaping (String, String, String) async -> Bool
    ) {
        self.users = users
        self.onConfirm = onConfirm
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                userPickerSection
                reasonSection
                pinSection
                consentSection
                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.bizarreError)
                            .accessibilityLabel("Error: \(err)")
                    }
                }
            }
            .navigationTitle("Impersonate User")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .toolbar { toolbarContent }
            .disabled(isProcessing)
            .overlay {
                if isProcessing {
                    ProgressView("Impersonating…")
                        .accessibilityLabel("Processing impersonation request")
                }
            }
        }
    }

    // MARK: - Sections

    private var userPickerSection: some View {
        Section("Select user to impersonate") {
            Picker("User", selection: $selectedUserId) {
                Text("Select a user…").tag("")
                ForEach(users) { user in
                    Text("\(user.displayName) (\(user.email))")
                        .tag(user.id)
                }
            }
            .accessibilityLabel("User to impersonate")
            .accessibilityIdentifier("impersonate.userPicker")
        }
    }

    private var reasonSection: some View {
        Section("Reason (required for audit log)") {
            TextField("e.g. Investigating customer complaint #1234", text: $reason, axis: .vertical)
                .lineLimit(3...5)
                .focused($focused, equals: .reason)
                .accessibilityLabel("Reason for impersonation")
                .accessibilityIdentifier("impersonate.reason")
        }
    }

    private var pinSection: some View {
        Section("Manager PIN") {
            HStack {
                SecureField("Enter manager PIN", text: $managerPin)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    #endif
                    .focused($focused, equals: .pin)
                    .accessibilityLabel("Manager PIN")
                    .accessibilityIdentifier("impersonate.pin")

                Button(showPINField ? "Hide" : "Show") {
                    showPINField.toggle()
                }
                .font(.caption)
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel(showPINField ? "Hide PIN" : "Show PIN")
            }
        }
    }

    private var consentSection: some View {
        Section {
            Toggle(isOn: $consentChecked) {
                Text("I understand this action will be recorded in the immutable audit log and is subject to compliance review.")
                    .font(.footnote)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Acknowledge audit log recording")
            .accessibilityIdentifier("impersonate.consent")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("impersonate.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Confirm") {
                Task { await confirmImpersonation() }
            }
            .disabled(!isFormValid || isProcessing)
            .accessibilityLabel("Confirm impersonation")
            .accessibilityIdentifier("impersonate.confirm")
        }
    }

    // MARK: - Logic

    private var isFormValid: Bool {
        !selectedUserId.isEmpty &&
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !managerPin.isEmpty &&
        consentChecked
    }

    private func confirmImpersonation() async {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }
        let success = await onConfirm(selectedUserId, reason, managerPin)
        if success {
            dismiss()
        } else {
            errorMessage = "Impersonation failed. Check your PIN and try again."
        }
    }

    // MARK: - Types

    private enum FocusedField: Hashable {
        case reason, pin
    }
}

// MARK: - UserRow

public struct UserRow: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let email: String

    public init(id: String, displayName: String, email: String) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }
}
