import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - Models

public enum SmsProvider: String, CaseIterable, Sendable {
    case bizarreCRMManaged = "bizarrecrm"
    case twilio = "twilio"
    case bandwidth = "bandwidth"

    public var displayName: String {
        switch self {
        case .bizarreCRMManaged: return "BizarreCRM Managed"
        case .twilio:            return "Twilio"
        case .bandwidth:         return "Bandwidth"
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class SmsProviderViewModel: Sendable {

    var selectedProvider: SmsProvider = .bizarreCRMManaged
    var fromNumber: String = ""
    var twilioAccountSid: String = ""
    var twilioAuthToken: String = ""
    var a2pStatus: String = ""
    // §19.10 — MMS support toggle
    var mmsEnabled: Bool = false

    var isLoading: Bool = false
    var isSaving: Bool = false
    var isSendingTest: Bool = false
    var errorMessage: String?
    var successMessage: String?

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let api else { return }
        do {
            let resp = try await api.fetchSmsSettings()
            selectedProvider = SmsProvider(rawValue: resp.provider ?? "") ?? .bizarreCRMManaged
            fromNumber = resp.fromNumber ?? ""
            twilioAccountSid = resp.twilioAccountSid ?? ""
            twilioAuthToken = resp.twilioAuthToken ?? ""
            a2pStatus = resp.a2pStatus ?? ""
            mmsEnabled = resp.mmsEnabled ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = SmsSettingsDTO(
                provider: selectedProvider.rawValue,
                fromNumber: fromNumber,
                twilioAccountSid: twilioAccountSid,
                twilioAuthToken: twilioAuthToken,
                a2pStatus: nil,
                mmsEnabled: mmsEnabled
            )
            _ = try await api.saveSmsSettings(body)
            successMessage = "SMS settings saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendTestSms() async {
        isSendingTest = true
        defer { isSendingTest = false }
        guard let api else { return }
        do {
            try await api.sendTestSms()
            successMessage = "Test SMS sent to your number."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct SmsProviderPage: View {
    @State private var vm: SmsProviderViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: SmsProviderViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Provider") {
                Picker("SMS provider", selection: $vm.selectedProvider) {
                    ForEach(SmsProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .accessibilityIdentifier("sms.provider")
            }

            // §19.10 — MMS toggle
            Section {
                Toggle("Enable MMS (photos & media)", isOn: $vm.mmsEnabled)
                    .accessibilityIdentifier("sms.mmsEnabled")
            } header: {
                Text("Messaging capabilities")
            } footer: {
                Text("MMS allows sending photos and media files. Only available if your SMS plan and carrier support it.")
            }

            Section("From number") {
                TextField("+1 (555) 000-0000", text: $vm.fromNumber)
                    #if canImport(UIKit)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif
                    .accessibilityLabel("From phone number")
                    .accessibilityIdentifier("sms.fromNumber")

                if !vm.a2pStatus.isEmpty {
                    LabeledContent("A2P 10DLC status") {
                        Text(vm.a2pStatus)
                            .foregroundStyle(vm.a2pStatus.lowercased() == "registered"
                                             ? .bizarreSuccess : .bizarreWarning)
                    }
                    .accessibilityLabel("A2P registration status: \(vm.a2pStatus)")
                }
            }

            if vm.selectedProvider == .twilio {
                Section("Twilio credentials") {
                    TextField("Account SID", text: $vm.twilioAccountSid)
                        #if canImport(UIKit)
                        .autocapitalization(.none)
                        #endif
                        .accessibilityLabel("Twilio Account SID")
                        .accessibilityIdentifier("sms.twilioSid")
                    SecureField("Auth token", text: $vm.twilioAuthToken)
                        .accessibilityLabel("Twilio Auth token")
                        .accessibilityIdentifier("sms.twilioToken")
                }
            }

            Section {
                Button {
                    Task { await vm.sendTestSms() }
                } label: {
                    if vm.isSendingTest {
                        ProgressView().accessibilityLabel("Sending test SMS")
                    } else {
                        Label("Send test SMS to my number", systemImage: "paperplane")
                    }
                }
                .disabled(vm.isSendingTest || vm.fromNumber.isEmpty)
                .accessibilityIdentifier("sms.sendTest")
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
                        .accessibilityLabel(msg)
                }
            }
        }
        .navigationTitle("SMS Provider")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("sms.save")
            }
        }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading {
                ProgressView().accessibilityLabel("Loading SMS settings")
            }
        }
    }
}
