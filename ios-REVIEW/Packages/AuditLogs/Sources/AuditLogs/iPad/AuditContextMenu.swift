import SwiftUI
import Core
import DesignSystem

/// §22 — Context menu items for an audit log row on iPad.
///
/// Provides four actions:
///   1. Copy entity ID — copies `entityKind #entityId` to the pasteboard.
///   2. Copy action    — copies the raw action string (e.g. "ticket.update").
///   3. Filter by actor — narrows the list to events by the same actor.
///   4. Open entity   — deep-links to the affected entity (if navigateToEntity is wired).
///
/// Usage (inside `.contextMenu { … }`):
/// ```swift
/// .contextMenu {
///     AuditContextMenu(
///         entry: entry,
///         onFilterByActor: { actorId in vm.applyActorFilter(actorId) },
///         onOpenEntity: navigateToEntity
///     )
/// }
/// ```
public struct AuditContextMenu: View {

    private let entry: AuditLogEntry
    private let onFilterByActor: ((_ actorId: String) -> Void)?
    private let onOpenEntity: ((_ entityType: String, _ entityId: String) -> Void)?

    public init(
        entry: AuditLogEntry,
        onFilterByActor: ((_ actorId: String) -> Void)? = nil,
        onOpenEntity: ((_ entityType: String, _ entityId: String) -> Void)? = nil
    ) {
        self.entry = entry
        self.onFilterByActor = onFilterByActor
        self.onOpenEntity = onOpenEntity
    }

    public var body: some View {
        // Action 1: Copy entity ID
        if let entityId = entry.entityId {
            Button {
                copyToPasteboard("\(entry.entityKind) #\(entityId)")
            } label: {
                Label("Copy Entity ID", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("contextmenu.copyEntityId.\(entry.id)")
        }

        // Action 2: Copy action string
        Button {
            copyToPasteboard(entry.action)
        } label: {
            Label("Copy Action", systemImage: "doc.on.clipboard")
        }
        .accessibilityIdentifier("contextmenu.copyAction.\(entry.id)")

        Divider()

        // Action 3: Filter by actor
        if let actorId = entry.actorUserId {
            Button {
                onFilterByActor?(String(actorId))
            } label: {
                Label("Filter by \(entry.actorName)", systemImage: "person.crop.circle.badge.checkmark")
            }
            .accessibilityIdentifier("contextmenu.filterByActor.\(entry.id)")
        }

        // Action 4: Open entity (deep-link)
        if let entityId = entry.entityId, onOpenEntity != nil {
            Button {
                onOpenEntity?(entry.entityKind, String(entityId))
            } label: {
                Label("Open \(entry.entityKind.capitalized)", systemImage: "arrow.right.circle")
            }
            .accessibilityIdentifier("contextmenu.openEntity.\(entry.id)")
        }
    }

    // MARK: - Pasteboard helper

    private func copyToPasteboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
