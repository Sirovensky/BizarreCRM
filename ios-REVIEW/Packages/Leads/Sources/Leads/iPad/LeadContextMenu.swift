import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - LeadContextMenuAction

/// The four context-menu actions available on a lead row.
public enum LeadContextMenuAction: Sendable {
    case convertToCustomer
    case changeStatus(String)
    case assign
    case archive
}

// MARK: - LeadContextMenu

/// Context-menu modifier for iPad lead list rows.
///
/// Provides four actions:
/// 1. Convert to Customer (hidden once already converted)
/// 2. Change Status  — sub-menu of available statuses
/// 3. Assign         — opens an assignment sheet
/// 4. Archive / Mark as Lost
///
/// Apply with `.leadContextMenu(lead:api:onAction:)` convenience.
public struct LeadContextMenu: ViewModifier {
    let lead: Lead
    let onAction: (LeadContextMenuAction) -> Void

    // Available status transitions — excludes the current status.
    private let kAllStatuses: [(value: String, label: String)] = [
        ("new",       "New"),
        ("contacted", "Contacted"),
        ("qualified", "Qualified"),
        ("converted", "Converted"),
        ("lost",      "Lost"),
    ]

    public init(lead: Lead, onAction: @escaping (LeadContextMenuAction) -> Void) {
        self.lead = lead
        self.onAction = onAction
    }

    public func body(content: Content) -> some View {
        content.contextMenu {
            // Convert to Customer — only shown for non-converted leads.
            if lead.status != "converted" {
                Button {
                    onAction(.convertToCustomer)
                } label: {
                    Label("Convert to Customer", systemImage: "arrow.right.circle")
                }
                .accessibilityLabel("Convert \(lead.displayName) to customer")
            }

            // Change Status sub-menu.
            Menu {
                ForEach(availableStatuses, id: \.value) { item in
                    Button {
                        onAction(.changeStatus(item.value))
                    } label: {
                        Label(item.label, systemImage: statusIcon(item.value))
                    }
                    .accessibilityLabel("Set status to \(item.label)")
                }
            } label: {
                Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityLabel("Change status for \(lead.displayName)")

            // Assign.
            Button {
                onAction(.assign)
            } label: {
                Label("Assign", systemImage: "person.badge.plus")
            }
            .accessibilityLabel("Assign \(lead.displayName)")

            Divider()

            // Archive / Mark as Lost — destructive.
            Button(role: .destructive) {
                onAction(.archive)
            } label: {
                Label("Archive (Mark Lost)", systemImage: "archivebox")
            }
            .accessibilityLabel("Archive \(lead.displayName)")
        }
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Private helpers

    private var availableStatuses: [(value: String, label: String)] {
        kAllStatuses.filter { $0.value != lead.status }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "new":       return "star"
        case "contacted": return "phone"
        case "qualified": return "checkmark.seal"
        case "converted": return "arrow.right.circle"
        case "lost":      return "xmark.circle"
        default:          return "circle"
        }
    }
}

// MARK: - View extension

public extension View {
    /// Applies the standard Leads context menu to a list row.
    ///
    /// - Parameters:
    ///   - lead: The lead this row represents.
    ///   - onAction: Closure called when the user picks an action.
    func leadContextMenu(
        lead: Lead,
        onAction: @escaping (LeadContextMenuAction) -> Void
    ) -> some View {
        modifier(LeadContextMenu(lead: lead, onAction: onAction))
    }
}
