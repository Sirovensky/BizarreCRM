// Core/Mac/MacRowContextMenu.swift
//
// `.macRowContextMenu(…)` — convenience wrapper around `.contextMenu` that
// builds a standard right-click menu on Mac (Designed for iPad) and iPad,
// using descriptors from `MacContextMenuCatalog.Actions`.
//
// On iPhone we still attach the menu so long-press surfaces the same actions,
// but consumers may prefer a swipe action there — pass `iPhoneEnabled: false`
// to suppress.
//
// §23.3 Mac polish — right-click context menus on every tappable element.
//
// Usage:
// ```swift
// TicketRow(ticket)
//     .macRowContextMenu(
//         onOpen:    { coordinator.openTicket(ticket) },
//         onEdit:    { coordinator.editTicket(ticket) },
//         onCopyID:  { UIPasteboard.general.string = ticket.publicID },
//         onArchive: { viewModel.archive(ticket) },
//         onDelete:  { viewModel.delete(ticket) }
//     )
// ```

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - View extension

public extension View {

    /// Attaches the standard BizarreCRM row context menu (Open / Edit / Copy
    /// ID / Archive / Delete).
    ///
    /// Each callback is optional — pass `nil` to omit the corresponding entry.
    /// At least one callback must be non-nil; otherwise the wrapper is a
    /// no-op (avoids attaching an empty menu).
    ///
    /// On iPhone the menu still appears via long-press unless
    /// `iPhoneEnabled` is `false`.
    ///
    /// - Parameters:
    ///   - onOpen: Optional open / view action (⌘O on Mac).
    ///   - onEdit: Optional edit action.
    ///   - onCopyID: Optional copy-id action.
    ///   - onShare: Optional share action.
    ///   - onArchive: Optional archive action.
    ///   - onDelete: Optional destructive delete action.
    ///   - iPhoneEnabled: When `false`, skip the menu on iPhone (default `true`).
    @ViewBuilder
    func macRowContextMenu(
        onOpen: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onCopyID: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onArchive: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        iPhoneEnabled: Bool = true
    ) -> some View {
        let hasAny =
            onOpen != nil ||
            onEdit != nil ||
            onCopyID != nil ||
            onShare != nil ||
            onArchive != nil ||
            onDelete != nil

        if !hasAny || (!iPhoneEnabled && MacRowContextMenuPlatform.isPhone) {
            self
        } else {
            self.contextMenu {
                if let onOpen {
                    MacContextMenuCatalog.Actions.open.button(action: onOpen)
                }
                if let onEdit {
                    MacContextMenuCatalog.Actions.edit.button(action: onEdit)
                }
                if let onCopyID {
                    MacContextMenuCatalog.Actions.copyID.button(action: onCopyID)
                }
                if let onShare {
                    MacContextMenuCatalog.Actions.share.button(action: onShare)
                }
                if onArchive != nil || onDelete != nil {
                    Divider()
                }
                if let onArchive {
                    MacContextMenuCatalog.Actions.archive.button(action: onArchive)
                }
                if let onDelete {
                    MacContextMenuCatalog.Actions.delete.button(action: onDelete)
                }
            }
        }
    }
}

// MARK: - Platform helper

/// Internal helper isolating the `UIDevice` lookup so the public API stays
/// pure SwiftUI.  Marked `@MainActor` to satisfy Swift 6 strict concurrency.
enum MacRowContextMenuPlatform {
    static var isPhone: Bool {
        #if canImport(UIKit)
        if ProcessInfo.processInfo.isiOSAppOnMac { return false }
        return UITraitCollection.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
}
