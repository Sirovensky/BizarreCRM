import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - TemporarySuspensionView
//
// §14.x Temporary suspension: suspend without offboarding (vacation without pay).
// Account is disabled until manager manually resumes.
//
// Server endpoint: PATCH /api/v1/settings/users/:id with body { is_suspended: true/false }
// A suspended employee:
//   • Cannot log in.
//   • Account is NOT deleted or archived.
//   • Shifts remain intact; they are not transferred.
//   • Manager can resume by toggling back.
//   • Audit log entry created server-side.
//
// Differs from Deactivate: deactivation is semi-permanent (greyed in list);
// suspension is explicitly temporary and shown with a distinct badge.

@MainActor
@Observable
public final class TemporarySuspensionViewModel {
    public enum State: Sendable, Equatable {
        case active
        case suspended
    }

    public private(set) var suspensionState: State = .active
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    public var showSuspendConfirm: Bool = false
    public var showResumeConfirm: Bool = false

    @ObservationIgnored private let employeeId: Int64
    @ObservationIgnored private let api: APIClient

    public init(employeeId: Int64, isSuspended: Bool = false, api: APIClient) {
        self.employeeId = employeeId
        self.suspensionState = isSuspended ? .suspended : .active
        self.api = api
    }

    public func suspend() async {
        isLoading = true
        errorMessage = nil
        do {
            try await api.setEmployeeSuspended(id: employeeId, isSuspended: true)
            suspensionState = .suspended
        } catch {
            AppLog.ui.error("Suspend failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
        showSuspendConfirm = false
    }

    public func resume() async {
        isLoading = true
        errorMessage = nil
        do {
            try await api.setEmployeeSuspended(id: employeeId, isSuspended: false)
            suspensionState = .active
        } catch {
            AppLog.ui.error("Resume failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
        showResumeConfirm = false
    }
}

public struct TemporarySuspensionView: View {
    @State private var vm: TemporarySuspensionViewModel
    private let employeeName: String

    public init(employeeId: Int64, isSuspended: Bool, employeeName: String, api: APIClient) {
        self.employeeName = employeeName
        _vm = State(wrappedValue: TemporarySuspensionViewModel(
            employeeId: employeeId,
            isSuspended: isSuspended,
            api: api
        ))
    }

    init(viewModel: TemporarySuspensionViewModel, employeeName: String) {
        self.employeeName = employeeName
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            statusBadge

            if let err = vm.errorMessage {
                Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
            }

            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                actionButton
            }
        }
        .confirmationDialog(
            "Suspend \(employeeName)?",
            isPresented: $vm.showSuspendConfirm,
            titleVisibility: .visible
        ) {
            Button("Suspend Account", role: .destructive) {
                Task { await vm.suspend() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(employeeName) will be unable to log in until the suspension is lifted. Shifts and data remain intact.")
        }
        .confirmationDialog(
            "Resume \(employeeName)?",
            isPresented: $vm.showResumeConfirm,
            titleVisibility: .visible
        ) {
            Button("Resume Access") {
                Task { await vm.resume() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(employeeName) will be able to log in again.")
        }
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        HStack(spacing: BrandSpacing.sm) {
            switch vm.suspensionState {
            case .active:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Active").font(.brandLabelSmall()).foregroundStyle(.green)
            case .suspended:
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                Text("Suspended").font(.brandLabelSmall()).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(
            vm.suspensionState == .suspended
                ? Color.orange.opacity(0.1)
                : Color.green.opacity(0.1),
            in: Capsule()
        )
        .accessibilityLabel("Account status: \(vm.suspensionState == .suspended ? "Suspended" : "Active")")
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch vm.suspensionState {
        case .active:
            Button(role: .destructive) {
                vm.showSuspendConfirm = true
            } label: {
                Label("Temporarily Suspend", systemImage: "pause.circle")
            }
            .accessibilityIdentifier("suspension.suspend")

        case .suspended:
            Button {
                vm.showResumeConfirm = true
            } label: {
                Label("Resume Access", systemImage: "play.circle")
            }
            .tint(.green)
            .accessibilityIdentifier("suspension.resume")
        }
    }
}

// MARK: - API extension

public extension APIClient {
    /// `PATCH /api/v1/settings/users/:id` with `{ is_suspended: Bool }`.
    func setEmployeeSuspended(id: Int64, isSuspended: Bool) async throws {
        _ = try await patch(
            "/api/v1/settings/users/\(id)",
            body: SetSuspendedBody(isSuspended: isSuspended),
            as: SetSuspendedResponse.self
        )
    }
}

private struct SetSuspendedBody: Encodable, Sendable {
    let isSuspended: Bool
    enum CodingKeys: String, CodingKey { case isSuspended = "is_suspended" }
}
private struct SetSuspendedResponse: Decodable, Sendable { let success: Bool? }
