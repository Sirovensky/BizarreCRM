#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateRejectSheet (§8.2)
//
// Staff rejects an estimate on behalf of the customer.
// Reason is required. Calls `PUT /api/v1/estimates/:id` with status=rejected.

@MainActor
@Observable
public final class EstimateRejectViewModel {
    public var reason: String = ""
    public private(set) var isRejecting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didReject: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let estimateId: Int64

    public init(api: APIClient, estimateId: Int64) {
        self.api = api
        self.estimateId = estimateId
    }

    public var canReject: Bool { !reason.trimmingCharacters(in: .whitespaces).isEmpty }

    public func reject() async {
        guard canReject else { return }
        isRejecting = true
        errorMessage = nil
        defer { isRejecting = false }
        do {
            try await api.rejectEstimate(estimateId: estimateId, reason: reason.trimmingCharacters(in: .whitespaces))
            didReject = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct EstimateRejectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EstimateRejectViewModel
    private let orderId: String

    public init(estimateId: Int64, orderId: String, api: APIClient) {
        self.orderId = orderId
        _vm = State(wrappedValue: EstimateRejectViewModel(api: api, estimateId: estimateId))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Rejection reason") {
                    TextField(
                        "Reason (required)",
                        text: Binding(get: { vm.reason }, set: { vm.reason = $0 }),
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .accessibilityLabel("Rejection reason — required")
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                            .accessibilityLabel("Error: \(err)")
                    }
                }

                if vm.didReject {
                    Section {
                        Label("Estimate rejected", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.bizarreError)
                            .accessibilityLabel("Estimate has been rejected")
                    }
                }
            }
            .navigationTitle("Reject \(orderId)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel rejection")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.didReject {
                        Button("Done") { dismiss() }
                            .accessibilityLabel("Dismiss rejection sheet")
                    } else {
                        Button("Reject") { Task { await vm.reject() } }
                            .disabled(!vm.canReject || vm.isRejecting)
                            .accessibilityLabel("Confirm rejection of this estimate")
                    }
                }
            }
            .overlay {
                if vm.isRejecting {
                    ProgressView("Rejecting…")
                        .padding(BrandSpacing.xl)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                }
            }
        }
    }
}
#endif
