import SwiftUI
import DesignSystem

// MARK: - FullExportConfirmSheet

/// Confirm dialog shown before starting a full tenant export.
/// Collects the encryption passphrase and explains what is included.
public struct FullExportConfirmSheet: View {

    @Bindable var viewModel: DataExportViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPassphraseFocused: Bool

    public init(viewModel: DataExportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                warningSection
                passphraseSection
                whatIsIncludedSection
            }
            .navigationTitle("Confirm Export")
            .exportInlineTitleMode()
            .toolbar { toolbarContent }
            .exportToolbarBackground()
            .disabled(viewModel.isLoading)
        }
        .presentationDetents([.medium, .large])
        .onAppear { isPassphraseFocused = true }
    }

    // MARK: - Sections

    private var warningSection: some View {
        Section {
            Label {
                Text("This exports **all tenant data**: customers, tickets, invoices, inventory, photos, and communications — packed as a password-encrypted ZIP.")
            } icon: {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Data Export")
        }
    }

    private var passphraseSection: some View {
        Section {
            SecureField("Encryption passphrase", text: $viewModel.passphrase)
                .focused($isPassphraseFocused)
                .textContentType(.password)
                .accessibilityLabel("Encryption passphrase")
                .accessibilityHint("Required to protect the export. Keep it safe — there is no recovery.")

            if viewModel.passphrase.count < 8 && !viewModel.passphrase.isEmpty {
                Text("Passphrase must be at least 8 characters.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Passphrase too short")
            }
        } header: {
            Text("Encryption")
        } footer: {
            Text("Store this passphrase securely. Without it, the export cannot be decrypted.")
        }
    }

    private var whatIsIncludedSection: some View {
        Section("What's included") {
            ForEach(includedItems, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel export")
        }
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.isLoading {
                ProgressView()
                    .accessibilityLabel("Starting export…")
            } else {
                Button("Start Export") {
                    Task { await viewModel.confirmTenantExport() }
                }
                .disabled(viewModel.passphrase.count < 8)
                .accessibilityLabel("Start export")
                .accessibilityHint("Begins the encrypted data export process")
            }
        }
    }

    // MARK: - Data

    private let includedItems: [String] = [
        "Customers & contact history",
        "Tickets & service jobs",
        "Invoices & payments",
        "Inventory items",
        "Photos & attachments",
        "Employee records",
        "SMS communications",
        "Audit logs"
    ]
}
