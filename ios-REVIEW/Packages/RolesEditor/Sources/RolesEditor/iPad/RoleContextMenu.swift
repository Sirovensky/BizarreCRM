import SwiftUI

// MARK: - RoleContextMenu
//
// Context menu items for a role row in the iPad sidebar.
// Displayed via `.contextMenu` modifier in RoleSidebar.
//
// Actions:
//   Duplicate Role — clones capabilities into a new role (via onDuplicate)
//   Rename         — triggers inline rename alert (via onRename)
//   Delete         — confirms via destructive dialog before calling real
//                    DELETE /api/v1/roles/:id (via onDelete → RolesMatrixViewModel)
//
// This view is a pure @ViewBuilder content provider — it holds no state.

public struct RoleContextMenu: View {

    // MARK: Inputs

    let role: Role
    let onDuplicate: (Role) -> Void
    let onRename: (Role) -> Void
    let onDelete: (Role) -> Void

    // MARK: Init

    public init(
        role: Role,
        onDuplicate: @escaping (Role) -> Void,
        onRename: @escaping (Role) -> Void,
        onDelete: @escaping (Role) -> Void
    ) {
        self.role = role
        self.onDuplicate = onDuplicate
        self.onRename = onRename
        self.onDelete = onDelete
    }

    // MARK: Body

    public var body: some View {
        // Duplicate
        Button {
            onDuplicate(role)
        } label: {
            Label("Duplicate Role", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Duplicate \(role.name)")

        // Rename
        Button {
            onRename(role)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        .accessibilityLabel("Rename \(role.name)")

        Divider()

        // Delete — destructive; confirmation dialog is handled by the parent view
        Button(role: .destructive) {
            onDelete(role)
        } label: {
            Label("Delete Role", systemImage: "trash")
        }
        .accessibilityLabel("Delete \(role.name)")
    }
}
