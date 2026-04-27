import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - OffboardingView
//
// §14.x Offboarding: Settings → Team → staff detail → Offboard.
//
// Actions performed server-side on confirm:
//   1. Immediately revoke access (deactivate account)
//   2. Sign out all active sessions for this user
//   3. Transfer assigned tickets to a selected manager
//   4. Archive shift history (kept for payroll records)
//
// Server endpoint: POST /api/v1/settings/users/:id/offboard
//   Body: { transfer_tickets_to_user_id: Int64?, export_shift_history: Bool }
//
// After offboarding, an optional shift-history PDF export is offered.
// Audit log entry is created server-side.

@MainActor
@Observable
public final class OffboardingViewModel {
    public enum Phase: Sendable, Equatable {
        case confirm
        case inProgress
        case done
        case failed(String)
    }

    public private(set) var phase: Phase = .confirm
    public var transferToEmployeeId: Int64? = nil
    public var exportShiftHistory: Bool = true
    public private(set) var availableManagers: [EmployeePickerItem] = []

    @ObservationIgnored private let employeeId: Int64
    @ObservationIgnored private let api: APIClient

    public init(employeeId: Int64, api: APIClient) {
        self.employeeId = employeeId
        self.api = api
    }

    public func loadManagers() async {
        do {
            availableManagers = try await api.listManagerPickerItems(excludingId: employeeId)
        } catch {
            AppLog.ui.error("Offboarding: loadManagers: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func offboard() async {
        phase = .inProgress
        do {
            try await api.offboardEmployee(
                id: employeeId,
                transferToUserId: transferToEmployeeId,
                exportShiftHistory: exportShiftHistory
            )
            phase = .done
        } catch {
            AppLog.ui.error("Offboarding failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

public struct OffboardingView: View {
    @State private var vm: OffboardingViewModel
    @Environment(\.dismiss) private var dismiss
    private let employeeName: String

    public init(employeeId: Int64, employeeName: String, api: APIClient) {
        self.employeeName = employeeName
        _vm = State(wrappedValue: OffboardingViewModel(employeeId: employeeId, api: api))
    }

    init(viewModel: OffboardingViewModel, employeeName: String) {
        self.employeeName = employeeName
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Offboard Employee")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.phase == .inProgress)
                }
            }
            .task { await vm.loadManagers() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .confirm:  confirmForm
        case .inProgress:
            VStack(spacing: BrandSpacing.md) {
                ProgressView().scaleEffect(1.5)
                Text("Processing offboarding…")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done:     doneView
        case .failed(let msg): errorView(msg)
        }
    }

    // MARK: - Confirm form

    private var confirmForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                warningBanner

                // Transfer tickets
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Text("Transfer Assigned Tickets")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityAddTraits(.isHeader)
                    Text("Open tickets assigned to \(employeeName) will be reassigned to the selected manager.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if vm.availableManagers.isEmpty {
                        Text("No managers available — tickets will be reassigned to the account owner.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        Picker("Transfer to", selection: $vm.transferToEmployeeId) {
                            Text("Account Owner (default)").tag(Optional<Int64>.none)
                            ForEach(vm.availableManagers) { m in
                                Text(m.displayName).tag(Optional(m.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.bizarreOrange)
                    }
                }

                // Shift history
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Text("Shift History")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityAddTraits(.isHeader)
                    Toggle("Include shift history export", isOn: $vm.exportShiftHistory)
                        .tint(.bizarreOrange)
                    Text("Shift records are retained on the server for payroll purposes regardless of this setting.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                // Confirm button
                Button(role: .destructive) {
                    Task { await vm.offboard() }
                } label: {
                    Label("Offboard \(employeeName)", systemImage: "person.badge.minus.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreError)
                .accessibilityIdentifier("offboard.confirm")
            }
            .padding(BrandSpacing.lg)
        }
    }

    private var warningBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .font(.system(size: 22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("This action is irreversible in the current session.")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Access is revoked immediately. The account can be reactivated from Settings → Team → Inactive Employees.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("\(employeeName) has been offboarded.")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            Text("Access revoked. Sessions ended. Tickets transferred. Shift history archived.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("offboard.done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40)).foregroundStyle(.bizarreError)
            Text("Offboarding Failed")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try Again") { vm.phase = .confirm }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EmployeePickerItem

public struct EmployeePickerItem: Identifiable, Sendable, Decodable {
    public let id: Int64
    public let firstName: String?
    public let lastName: String?
    public let role: String?

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? "User #\(id)" : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, role
        case firstName = "first_name"
        case lastName  = "last_name"
    }
}

// MARK: - API extensions

public extension APIClient {
    /// `GET /api/v1/employees?role=manager,owner` — manager-level employees for picker.
    func listManagerPickerItems(excludingId: Int64) async throws -> [EmployeePickerItem] {
        let items = try await get(
            "/api/v1/employees",
            query: [URLQueryItem(name: "roles", value: "manager,owner")],
            as: [EmployeePickerItem].self
        )
        return items.filter { $0.id != excludingId }
    }

    /// `POST /api/v1/settings/users/:id/offboard` — offboard an employee.
    func offboardEmployee(
        id: Int64,
        transferToUserId: Int64?,
        exportShiftHistory: Bool
    ) async throws {
        _ = try await post(
            "/api/v1/settings/users/\(id)/offboard",
            body: OffboardBody(transferTicketsToUserId: transferToUserId, exportShiftHistory: exportShiftHistory),
            as: OffboardResponse.self
        )
    }
}

private struct OffboardBody: Encodable, Sendable {
    let transferTicketsToUserId: Int64?
    let exportShiftHistory: Bool
    enum CodingKeys: String, CodingKey {
        case transferTicketsToUserId = "transfer_tickets_to_user_id"
        case exportShiftHistory = "export_shift_history"
    }
}
private struct OffboardResponse: Decodable, Sendable { let success: Bool? }
