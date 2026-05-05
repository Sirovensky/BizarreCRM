import SwiftUI
import Networking

// MARK: - §22 Repair Pricing Context Menu

/// Reusable context-menu content for a `DeviceTemplate` row.
///
/// Provides four actions:
///   • Open   — select & navigate to the template
///   • Edit   — open the editor sheet/panel for the template
///   • Duplicate — async copy via API; caller handles the await
///   • Delete — triggers a confirmation; caller shows the alert
///
/// This is a `View` (not a modifier) so it composes naturally inside
/// `.contextMenu { }` and `.swipeActions { }` call sites.
///
/// Usage:
/// ```swift
/// .contextMenu {
///     RepairPricingContextMenu(
///         template: template,
///         onOpen:      { vm.open(template) },
///         onEdit:      { vm.edit(template) },
///         onDuplicate: { Task { await vm.duplicate(template) } },
///         onDelete:    { vm.requestDelete(template) }
///     )
/// }
/// ```
public struct RepairPricingContextMenu: View {
    public let template: DeviceTemplate

    public let onOpen: () -> Void
    public let onEdit: () -> Void
    public let onDuplicate: () -> Void
    /// Initiates the delete confirmation flow (does NOT delete immediately).
    public let onDelete: () -> Void

    public init(
        template: DeviceTemplate,
        onOpen: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.template = template
        self.onOpen = onOpen
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
    }

    public var body: some View {
        // Open
        Button(action: onOpen) {
            Label("Open", systemImage: "arrow.right.circle")
        }
        .accessibilityIdentifier("contextMenu.open")

        // Edit
        Button(action: onEdit) {
            Label("Edit", systemImage: "pencil")
        }
        .accessibilityIdentifier("contextMenu.edit")

        // Duplicate
        Button(action: onDuplicate) {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        .accessibilityIdentifier("contextMenu.duplicate")

        Divider()

        // Delete (destructive — shows confirmation)
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("contextMenu.delete")
    }
}

// MARK: - View extension convenience

public extension View {
    /// Attaches `RepairPricingContextMenu` to any view that represents a `DeviceTemplate`.
    func repairPricingContextMenu(
        template: DeviceTemplate,
        onOpen: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        contextMenu {
            RepairPricingContextMenu(
                template: template,
                onOpen: onOpen,
                onEdit: onEdit,
                onDuplicate: onDuplicate,
                onDelete: onDelete
            )
        }
    }
}
