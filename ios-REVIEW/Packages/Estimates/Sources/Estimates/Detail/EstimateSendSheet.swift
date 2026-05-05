#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateSendSheet (§8.2)
//
// Presents SMS / email send options for an estimate.
// On confirm calls `POST /api/v1/estimates/:id/send`.
// Server returns the approval link which is shown for copying.

@MainActor
@Observable
public final class EstimateSendViewModel {
    public var sendSms: Bool = false
    public var sendEmail: Bool = false
    public private(set) var isSending: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var approvalLink: String?
    public private(set) var didSend: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let estimateId: Int64

    public init(api: APIClient, estimateId: Int64) {
        self.api = api
        self.estimateId = estimateId
    }

    public func send() async {
        guard sendSms || sendEmail else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let response = try await api.sendEstimate(
                estimateId: estimateId,
                sendSms: sendSms ? true : nil,
                sendEmail: sendEmail ? true : nil
            )
            approvalLink = response.approvalLink
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct EstimateSendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EstimateSendViewModel
    private let orderId: String

    public init(estimateId: Int64, orderId: String, api: APIClient) {
        self.orderId = orderId
        _vm = State(wrappedValue: EstimateSendViewModel(api: api, estimateId: estimateId))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Send methods") {
                    Toggle("Send SMS to customer", isOn: Binding(
                        get: { vm.sendSms },
                        set: { vm.sendSms = $0 }
                    ))
                    .accessibilityLabel("Send estimate via SMS")

                    Toggle("Send email to customer", isOn: Binding(
                        get: { vm.sendEmail },
                        set: { vm.sendEmail = $0 }
                    ))
                    .accessibilityLabel("Send estimate via email")
                }

                if let link = vm.approvalLink {
                    Section("Approval link") {
                        Text(link)
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                            .accessibilityLabel("Approval link: \(link)")

                        Button {
                            UIPasteboard.general.string = link
                        } label: {
                            Label("Copy link", systemImage: "doc.on.doc")
                        }
                        .accessibilityLabel("Copy approval link to clipboard")
                    }
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                            .accessibilityLabel("Error: \(err)")
                    }
                }

                if vm.didSend {
                    Section {
                        Label("Estimate sent successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                            .accessibilityLabel("Estimate sent successfully")
                    }
                }
            }
            .navigationTitle("Send \(orderId)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel sending estimate")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.didSend {
                        Button("Done") { dismiss() }
                            .accessibilityLabel("Dismiss send sheet")
                    } else {
                        Button("Send") { Task { await vm.send() } }
                            .disabled(!vm.sendSms && !vm.sendEmail || vm.isSending)
                            .accessibilityLabel("Send estimate to customer")
                    }
                }
            }
            .overlay {
                if vm.isSending {
                    ProgressView("Sending…")
                        .padding(BrandSpacing.xl)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                }
            }
        }
    }
}
#endif
