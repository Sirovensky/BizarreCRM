#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §8.2 Estimate Reject Sheet
//
// Server route: PUT /api/v1/estimates/:id  { status: "rejected", notes: "<reason>" }
// A dedicated reject endpoint doesn't exist; we use the PUT update endpoint
// to flip status to "rejected" and append the reason to notes.
//
// Reason is required — the confirm button stays disabled until non-empty.

// MARK: - EstimateRejectSheetViewModel

@MainActor
@Observable
final class EstimateRejectSheetViewModel {
    var reason: String = ""
    var isSubmitting: Bool = false
    var errorMessage: String?
    var didReject: Bool = false

    private let api: APIClient
    let estimateId: Int64

    var canSubmit: Bool {
        !reason.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(api: APIClient, estimateId: Int64) {
        self.api = api
        self.estimateId = estimateId
    }

    func reject() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        struct RejectBody: Encodable {
            let status: String
            let notes: String
        }
        let body = RejectBody(status: "rejected", notes: reason)
        do {
            _ = try await api.put(
                "/api/v1/estimates/\(estimateId)",
                body: body,
                as: Estimate.self
            )
            didReject = true
            AppLog.ui.info("Estimate \(self.estimateId) rejected. Reason: \(self.reason, privacy: .private)")
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
            AppLog.ui.error("Estimate reject failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - EstimateRejectSheet

/// §8.2 Reject-reason sheet — reason is required before Submit is enabled.
public struct EstimateRejectSheet: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onRejected: @MainActor () -> Void

    @State private var vm: EstimateRejectSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var reasonFocused: Bool

    public init(
        estimate: Estimate,
        api: APIClient,
        onRejected: @escaping @MainActor () -> Void = {}
    ) {
        self.estimate = estimate
        self.api = api
        self.onRejected = onRejected
        _vm = State(wrappedValue: EstimateRejectSheetViewModel(
            api: api,
            estimateId: estimate.id
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    // Context card
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text("Rejecting \(estimate.orderId ?? "EST-?")")
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnSurface)
                        Text(estimate.customerName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .padding(BrandSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                    // Reason field
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        Text("Reason (required)")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurface)

                        TextEditor(text: $vm.reason)
                            .frame(minHeight: 100)
                            .padding(BrandSpacing.sm)
                            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .strokeBorder(
                                        vm.reason.trimmingCharacters(in: .whitespaces).isEmpty
                                            ? Color.bizarreOutline.opacity(0.3)
                                            : Color.bizarreOrange.opacity(0.6),
                                        lineWidth: 1
                                    )
                            )
                            .focused($reasonFocused)
                            .accessibilityLabel("Rejection reason. Required.")

                        Text("Explain why the estimate is being rejected. This is visible in the history timeline.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.brandLabelMedium())
                            .foregroundStyle(.bizarreError)
                            .padding(BrandSpacing.sm)
                            .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }

                    Spacer()
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle("Reject Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await vm.reject() }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Reject")
                                .fontWeight(.semibold)
                                .foregroundStyle(.bizarreError)
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .accessibilityLabel(vm.isSubmitting ? "Rejecting…" : "Confirm rejection")
                }
            }
            .onAppear { reasonFocused = true }
            .onChange(of: vm.didReject) { _, rejected in
                if rejected {
                    onRejected()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#endif
