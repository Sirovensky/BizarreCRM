import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EmployeeTableView
//
// §14.1 — iPad / Mac sortable Table view of employees.
// Displayed when `!Platform.isCompact`.
// Columns: Name / Email / Role / Status / Has PIN / Hours this week / Commission.
//
// Gated on Platform.isCompact in EmployeeListView so iPhone never sees this.

@available(iOS 16.0, macOS 13.0, *)
struct EmployeeTableView: View {

    // MARK: - Bindings / state

    let employees: [Employee]
    @Binding var selection: Employee?

    // Sort state
    @State private var sortOrder: [KeyPathComparator<Employee>] = [
        .init(\.displayName, order: .forward)
    ]

    // MARK: - Body

    var body: some View {
        Table(sortedEmployees, selection: $selection, sortOrder: $sortOrder) {
            // Name column
            TableColumn("Name", value: \.displayName) { emp in
                HStack(spacing: BrandSpacing.sm) {
                    ZStack {
                        Circle().fill(Color.bizarreOrangeContainer)
                        Text(emp.initials)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnOrange)
                    }
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                    Text(emp.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                }
                .hoverEffect(.highlight)
            }

            // Email column
            TableColumn("Email") { emp in
                if let email = emp.email, !email.isEmpty {
                    Text(email)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                        .textSelection(.enabled)
                } else {
                    Text("—")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            // Role column
            TableColumn("Role") { emp in
                if let role = emp.role, !role.isEmpty {
                    Text(role.capitalized)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                } else {
                    Text("—")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            // Status column
            TableColumn("Status") { emp in
                StatusBadge(active: emp.active)
            }

            // Has PIN column
            TableColumn("PIN Set") { emp in
                Image(systemName: emp.hasPin == 1 ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(emp.hasPin == 1 ? Color.green : Color.bizarreOnSurfaceMuted)
                    .accessibilityLabel(emp.hasPin == 1 ? "PIN set" : "No PIN")
            }

            // Role column variant — commission shown in detail; table shows role badge only
            TableColumn("Joined") { emp in
                if let at = emp.createdAt {
                    Text(String(at.prefix(10)))
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } else {
                    Text("—")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .tableStyle(.inset)
    }

    // MARK: - Sorting

    private var sortedEmployees: [Employee] {
        employees.sorted(using: sortOrder)
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let active: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(dotColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var dotColor: Color {
        active ? Color.green : Color.bizarreOnSurfaceMuted
    }

    private var label: String {
        active ? "Active" : "Inactive"
    }
}

// MARK: - Employee sortable conformance

extension Employee: Comparable {
    public static func < (lhs: Employee, rhs: Employee) -> Bool {
        lhs.displayName < rhs.displayName
    }
}
