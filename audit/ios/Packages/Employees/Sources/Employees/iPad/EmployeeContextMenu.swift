#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §22 — iPad Employee list-row context menu
//
// Four actions per the spec:
//   1. Open       — navigate to detail (selects in split view)
//   2. Assign Role — shows role picker sheet
//   3. Deactivate / Reactivate — toggle active flag with confirmation
//   4. Clock In / Clock Out    — start or end a shift

// MARK: - EmployeeContextMenu

/// Context-menu modifier for an employee row in the iPad 3-column list.
///
/// All mutation callbacks are `async`-closure based so the caller (the
/// three-column view) owns the API client and can coordinate state updates.
///
/// Usage:
/// ```swift
/// Row(employee: emp)
///     .modifier(EmployeeContextMenu(
///         employee: emp,
///         availableRoles: vm.availableRoles,
///         onOpen: { selectedEmployee = emp },
///         onAssignRole: { roleId in await vm.assignRole(emp, roleId: roleId) },
///         onToggleActive: { await vm.toggleActive(emp) },
///         onToggleClock: { await vm.toggleClock(emp) }
///     ))
/// ```
public struct EmployeeContextMenu: ViewModifier {

    // MARK: - Configuration

    public let employee: Employee
    public let availableRoles: [RoleRow]
    public let onOpen: () -> Void
    public let onAssignRole: (Int) async -> Void
    public let onToggleActive: () async -> Void
    public let onToggleClock: () async -> Void

    // MARK: - Init

    public init(
        employee: Employee,
        availableRoles: [RoleRow] = [],
        onOpen: @escaping () -> Void,
        onAssignRole: @escaping (Int) async -> Void,
        onToggleActive: @escaping () async -> Void,
        onToggleClock: @escaping () async -> Void
    ) {
        self.employee = employee
        self.availableRoles = availableRoles
        self.onOpen = onOpen
        self.onAssignRole = onAssignRole
        self.onToggleActive = onToggleActive
        self.onToggleClock = onToggleClock
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .contextMenu {
                // 1. Open
                Button {
                    onOpen()
                } label: {
                    Label("Open", systemImage: "person.crop.circle")
                }
                .accessibilityLabel("Open employee detail for \(employee.displayName)")

                Divider()

                // 2. Assign Role
                if !availableRoles.isEmpty {
                    Menu {
                        ForEach(availableRoles) { role in
                            Button {
                                Task { await onAssignRole(role.id) }
                            } label: {
                                if role.name == employee.role {
                                    Label(role.name.capitalized, systemImage: "checkmark")
                                } else {
                                    Text(role.name.capitalized)
                                }
                            }
                            .accessibilityLabel("Assign role \(role.name.capitalized)")
                        }
                    } label: {
                        Label("Assign Role", systemImage: "person.badge.key")
                    }
                    .accessibilityLabel("Assign role to \(employee.displayName)")
                }

                Divider()

                // 3. Clock In / Clock Out
                Button {
                    Task { await onToggleClock() }
                } label: {
                    Label(
                        employee.active ? "Clock In / Out" : "Clock In / Out (inactive)",
                        systemImage: "clock.badge"
                    )
                }
                .accessibilityLabel("Toggle clock in or out for \(employee.displayName)")
                .disabled(!employee.active)

                Divider()

                // 4. Deactivate / Reactivate (destructive if active)
                Button(role: employee.active ? .destructive : .none) {
                    Task { await onToggleActive() }
                } label: {
                    Label(
                        employee.active ? "Deactivate" : "Reactivate",
                        systemImage: employee.active
                            ? "person.crop.circle.badge.minus"
                            : "person.crop.circle.badge.plus"
                    )
                }
                .accessibilityLabel(
                    employee.active
                        ? "Deactivate \(employee.displayName)"
                        : "Reactivate \(employee.displayName)"
                )
            }
    }
}

// MARK: - View convenience

public extension View {
    /// Attaches the §22 employee context menu.
    func employeeContextMenu(
        employee: Employee,
        availableRoles: [RoleRow] = [],
        onOpen: @escaping () -> Void,
        onAssignRole: @escaping (Int) async -> Void,
        onToggleActive: @escaping () async -> Void,
        onToggleClock: @escaping () async -> Void
    ) -> some View {
        modifier(EmployeeContextMenu(
            employee: employee,
            availableRoles: availableRoles,
            onOpen: onOpen,
            onAssignRole: onAssignRole,
            onToggleActive: onToggleActive,
            onToggleClock: onToggleClock
        ))
    }
}

#endif
