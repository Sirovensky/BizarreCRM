import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PTOManagerApprovalSheet
//
// §14.9 — Manager approve / deny time-off requests.
// Surfaced from the time-off requests sidebar in the shift schedule view
// or from the employee detail screen.
//
// Server:
//   POST /api/v1/time-off/:id/approve  → approved TimeOffRequest
//   POST /api/v1/time-off/:id/deny     → denied TimeOffRequest (body: { reason })

@MainActor
@Observable
public final class PTOManagerApprovalViewModel {
    public private(set) var isProcessing = false
    public private(set) var errorMessage: String?
    public private(set) var processedRequest: TimeOffRequest?

    public var denialReason: String = ""

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func approve(requestId: Int64) async {
        isProcessing = true
        defer { isProcessing = false }
        errorMessage = nil
        do {
            processedRequest = try await api.approveTimeOff(id: requestId)
            AppLog.ui.info("PTO approved: id=\(requestId, privacy: .public)")
        } catch {
            AppLog.ui.error("PTO approve failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func deny(requestId: Int64) async {
        isProcessing = true
        defer { isProcessing = false }
        errorMessage = nil
        do {
            processedRequest = try await api.denyTimeOff(
                id: requestId,
                reason: denialReason.isEmpty ? nil : denialReason
            )
            AppLog.ui.info("PTO denied: id=\(requestId, privacy: .public)")
        } catch {
            AppLog.ui.error("PTO deny failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func reset() {
        processedRequest = nil
        errorMessage = nil
        denialReason = ""
    }
}

public struct PTOManagerApprovalSheet: View {
    let request: TimeOffRequest
    let onDecision: (TimeOffRequest) -> Void

    @State private var vm: PTOManagerApprovalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDenyReasonField = false

    public init(request: TimeOffRequest, api: APIClient, onDecision: @escaping (TimeOffRequest) -> Void) {
        self.request = request
        self.onDecision = onDecision
        _vm = State(wrappedValue: PTOManagerApprovalViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    // Request summary
                    VStack(spacing: BrandSpacing.sm) {
                        Text(request.employeeDisplayName)
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Text(request.kind.displayName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        HStack {
                            Label(request.startDate.prefix(10) == request.endDate.prefix(10)
                                  ? String(request.startDate.prefix(10))
                                  : "\(String(request.startDate.prefix(10))) – \(String(request.endDate.prefix(10)))",
                                  systemImage: "calendar")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        if let reason = request.reason, !reason.isEmpty {
                            Text("Reason: \(reason)")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(BrandSpacing.lg)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                    .accessibilityElement(children: .combine)

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Error: \(err)")
                    }

                    if showDenyReasonField {
                        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                            Text("Denial Reason (optional)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            TextField("Reason for denial", text: $vm.denialReason, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Denial reason")
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Action buttons
                    if vm.isProcessing {
                        ProgressView("Processing…")
                    } else if let result = vm.processedRequest {
                        VStack(spacing: BrandSpacing.xs) {
                            Image(systemName: result.status == .approved
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(result.status == .approved ? Color.green : Color.bizarreError)
                                .accessibilityHidden(true)
                            Text(result.status == .approved ? "Request Approved" : "Request Denied")
                                .font(.brandTitleMedium())
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                onDecision(result)
                                dismiss()
                            }
                        }
                    } else {
                        HStack(spacing: BrandSpacing.md) {
                            // Deny button
                            Button {
                                if showDenyReasonField {
                                    Task { await vm.deny(requestId: request.id) }
                                } else {
                                    withAnimation(.spring(response: 0.3)) {
                                        showDenyReasonField = true
                                    }
                                }
                            } label: {
                                Label(showDenyReasonField ? "Confirm Deny" : "Deny",
                                      systemImage: "xmark.circle")
                                    .font(.brandBodyMedium())
                                    .frame(maxWidth: .infinity)
                                    .padding(BrandSpacing.sm)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.bizarreError)
                            .accessibilityLabel(showDenyReasonField ? "Confirm denial" : "Deny request")

                            // Approve button
                            Button {
                                Task { await vm.approve(requestId: request.id) }
                            } label: {
                                Label("Approve", systemImage: "checkmark.circle")
                                    .font(.brandBodyMedium())
                                    .frame(maxWidth: .infinity)
                                    .padding(BrandSpacing.sm)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .accessibilityLabel("Approve request")
                        }
                    }

                    Spacer()
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle("Time-Off Request")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
