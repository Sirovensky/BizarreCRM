#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.2 — Assignee picker for ticket detail.
//
// Shows a searchable grid of employees. Tapping one calls PUT /tickets/:id
// with { assigned_to } and dismisses. "Assign to me" shortcut at the top
// pre-selects the current logged-in user (id from APIClient.currentUserId if available).
//
// Server route confirmed: PUT /api/v1/tickets/:id  (tickets.routes.ts)

// MARK: - ViewModel

@MainActor
@Observable
final class TicketAssigneePickerViewModel {
    private(set) var employees: [Employee] = []
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var errorMessage: String?
    private(set) var savedSuccessfully: Bool = false

    var searchText: String = ""

    var filtered: [Employee] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return employees }
        let lower = q.lowercased()
        return employees.filter { $0.displayName.lowercased().contains(lower) }
    }

    @ObservationIgnored private let api: APIClient
    let ticketId: Int64
    let currentAssigneeId: Int64?

    init(api: APIClient, ticketId: Int64, currentAssigneeId: Int64?) {
        self.api = api
        self.ticketId = ticketId
        self.currentAssigneeId = currentAssigneeId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            employees = try await api.ticketAssigneeCandidates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assign(employeeId: Int64, employeeName: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            struct AssignBody: Encodable, Sendable {
                let assignedTo: Int64
                enum CodingKeys: String, CodingKey { case assignedTo = "assigned_to" }
            }
            _ = try await api.put(
                "/api/v1/tickets/\(ticketId)",
                body: AssignBody(assignedTo: employeeId),
                as: TicketDetail.self
            )
            savedSuccessfully = true
        } catch {
            AppLog.ui.error("Assign ticket \(self.ticketId) failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func assignToMe(currentUserId: Int64?) async {
        guard let uid = currentUserId,
              let me = employees.first(where: { $0.id == uid }) else { return }
        await assign(employeeId: me.id, employeeName: me.displayName)
    }
}

// MARK: - View

/// §4.2 — Sheet presented from TicketDetailView when user taps "Assign" action.
/// iPhone: half-height sheet. iPad: popover.
public struct TicketAssigneePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketAssigneePickerViewModel
    let onAssigned: () -> Void

    public init(api: APIClient, ticketId: Int64, currentAssigneeId: Int64?, onAssigned: @escaping () -> Void) {
        _vm = State(wrappedValue: TicketAssigneePickerViewModel(
            api: api,
            ticketId: ticketId,
            currentAssigneeId: currentAssigneeId
        ))
        self.onAssigned = onAssigned
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Group {
                    if vm.isLoading {
                        ProgressView("Loading employees…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Loading employee list")
                    } else if let err = vm.errorMessage {
                        VStack(spacing: BrandSpacing.md) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 28)).foregroundStyle(.bizarreError)
                                .accessibilityHidden(true)
                            Text(err)
                                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                                .multilineTextAlignment(.center)
                            Button("Retry") { Task { await vm.load() } }
                                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
                        }
                        .padding(BrandSpacing.lg)
                    } else {
                        employeeList
                    }
                }
            }
            .navigationTitle("Assign Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search employees")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel assignee picker")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Assign to me") {
                        Task { await vm.assignToMe(currentUserId: nil) }
                    }
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Assign ticket to myself")
                    .disabled(vm.isSaving)
                }
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.savedSuccessfully) { _, success in
            if success { onAssigned(); dismiss() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Employee list

    private var employeeList: some View {
        List {
            if vm.filtered.isEmpty {
                Text("No employees found")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .listRowBackground(Color.bizarreSurface1)
            } else {
                ForEach(vm.filtered) { employee in
                    Button {
                        Task { await vm.assign(employeeId: employee.id, employeeName: employee.displayName) }
                    } label: {
                        EmployeeRow(employee: employee, isSelected: employee.id == vm.currentAssigneeId)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bizarreSurface1)
                    .hoverEffect(.highlight)
                    .disabled(vm.isSaving)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Employee row

private struct EmployeeRow: View {
    let employee: Employee
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            // Avatar circle with initials
            ZStack {
                Circle()
                    .fill(Color.bizarreOrange.opacity(0.15))
                    .frame(width: 38, height: 38)
                Text(employee.initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(employee.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let role = employee.role, !role.isEmpty {
                    Text(role.capitalized)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Currently assigned")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(employee.displayName)\(employee.role != nil ? ", \(employee.role!.capitalized)" : "")\(isSelected ? ", currently assigned" : "")")
    }
}
#endif
