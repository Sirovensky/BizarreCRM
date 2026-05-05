import SwiftUI
import DesignSystem
import Networking

/// §38 — Admin settings for Apple Wallet pass templates.
///
/// Accessible from Settings → Loyalty → Wallet Passes.
///
/// **Server contract:**
/// `POST /settings/wallet-pass-template` — body `WalletPassTemplateRequest`.
/// Returns `{ success: Bool, message: String? }`.
public struct WalletSettingsView: View {

    @State private var vm: WalletSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient) {
        _vm = State(wrappedValue: WalletSettingsViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            form
                .navigationTitle("Wallet Passes")
                .toolbar { toolbarItems }
                .alert("Error", isPresented: $vm.showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(vm.errorMessage)
                }
                .alert("Saved", isPresented: $vm.showSuccess) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Wallet pass template updated.")
                }
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            toggleSection
            if vm.walletEnabled {
                templateSection
            }
        }
    }

    private var toggleSection: some View {
        Section {
            Toggle("Enable Wallet passes", isOn: $vm.walletEnabled)
                .toggleStyle(.switch)
                .accessibilityLabel("Enable Apple Wallet passes")
                .accessibilityHint(
                    "When enabled, customers can add loyalty and gift card passes to Apple Wallet"
                )
        } footer: {
            Text(
                "Requires a valid Apple Pass Type certificate on the server. " +
                "Contact your administrator to configure pass signing."
            )
            .font(.brandLabelSmall())
        }
    }

    private var templateSection: some View {
        Section("Pass Template") {
            LabeledContent("Header line") {
                TextField("e.g. LOYALTY", text: $vm.headerLine)
                    .multilineTextAlignment(.trailing)
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Pass header line")
            }

            LabeledContent("Back — description") {
                TextField("e.g. Earn 1 point per $1", text: $vm.backDescription)
                    .multilineTextAlignment(.trailing)
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Pass back description")
            }

            LabeledContent("Back — website URL") {
                urlTextField
            }

            LabeledContent("Back — support phone") {
                phoneTextField
            }

            LabeledContent("Back — terms") {
                TextField("Points expire after 12 months…", text: $vm.backTerms, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Pass back terms and conditions")
            }
        }
    }

    // Separate @ViewBuilder for platform-conditional keyboard modifiers.
    @ViewBuilder
    private var urlTextField: some View {
        let base = TextField("https://bizarrecrm.com", text: $vm.backWebURL)
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
            .font(.brandBodyMedium())
            .accessibilityLabel("Pass back website URL")
#if canImport(UIKit)
        base
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
#else
        base
#endif
    }

    @ViewBuilder
    private var phoneTextField: some View {
        let base = TextField("+1 (555) 000-0000", text: $vm.backPhone)
            .multilineTextAlignment(.trailing)
            .font(.brandBodyMedium())
            .accessibilityLabel("Pass back support phone number")
#if canImport(UIKit)
        base.keyboardType(.phonePad)
#else
        base
#endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task { await vm.save() }
            }
            .disabled(vm.isSaving)
            .accessibilityLabel("Save Wallet pass template")
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel Wallet settings")
        }
    }
}

// MARK: - WalletSettingsViewModel

@MainActor
@Observable
public final class WalletSettingsViewModel {

    // MARK: - Form fields

    var walletEnabled: Bool = false
    var headerLine: String = ""
    var backDescription: String = ""
    var backWebURL: String = ""
    var backPhone: String = ""
    var backTerms: String = ""

    // MARK: - UI state

    var isSaving: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var showSuccess: Bool = false

    // MARK: - Private

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Actions

    func save() async {
        isSaving = true
        defer { isSaving = false }

        let body = WalletPassTemplateRequest(
            enabled: walletEnabled,
            headerLine: headerLine.isEmpty ? nil : headerLine,
            backDescription: backDescription.isEmpty ? nil : backDescription,
            backWebURL: backWebURL.isEmpty ? nil : backWebURL,
            backPhone: backPhone.isEmpty ? nil : backPhone,
            backTerms: backTerms.isEmpty ? nil : backTerms
        )

        do {
            _ = try await api.post(
                "/settings/wallet-pass-template",
                body: body,
                as: EmptyAPIResponse.self
            )
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Request / Response DTOs

struct WalletPassTemplateRequest: Encodable, Sendable {
    let enabled: Bool
    let headerLine: String?
    let backDescription: String?
    let backWebURL: String?
    let backPhone: String?
    let backTerms: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case headerLine      = "header_line"
        case backDescription = "back_description"
        case backWebURL      = "back_web_url"
        case backPhone       = "back_phone"
        case backTerms       = "back_terms"
    }
}

struct EmptyAPIResponse: Decodable, Sendable {}
