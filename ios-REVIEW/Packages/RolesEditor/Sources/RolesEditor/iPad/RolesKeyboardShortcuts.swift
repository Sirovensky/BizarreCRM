import SwiftUI

// MARK: - RolesKeyboardShortcuts
//
// Invisible overlay view that registers all Roles-editor keyboard shortcuts
// for iPad (and Mac via Designed-for-iPad).
//
// Registered shortcuts:
//   ⌘N  — New role
//   ⌘F  — Focus search (sidebar search field gains focus via searchable)
//   ⌘R  — Rename selected role
//   ⌘D  — Duplicate selected role
//
// Usage: add as a `.background(RolesKeyboardShortcuts(...))` on the
// NavigationSplitView so the shortcuts are in scope regardless of which
// column has focus.
//
// NOTE: ⌘N and ⌘F are also registered directly on buttons in the toolbar
// for discoverability in the system shortcut HUD. This overlay handles
// ⌘R and ⌘D which have no corresponding toolbar button.

public struct RolesKeyboardShortcuts: View {

    // MARK: Inputs

    let selectedRole: Role?
    let onNew: () -> Void
    let onDuplicate: () -> Void
    let onRename: () -> Void

    // MARK: Init

    public init(
        selectedRole: Role?,
        onNew: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onRename: @escaping () -> Void
    ) {
        self.selectedRole = selectedRole
        self.onNew = onNew
        self.onDuplicate = onDuplicate
        self.onRename = onRename
    }

    // MARK: Body

    public var body: some View {
        // Zero-size transparent view — purely for shortcut registration.
        // ⌘N is registered on the toolbar button directly; this overlay
        // only adds ⌘R (Rename) and ⌘D (Duplicate) which have no toolbar equivalent.
        Color.clear
            .frame(width: 0, height: 0)
            .background(roleShortcutButtons)
    }

    @ViewBuilder
    private var roleShortcutButtons: some View {
        // Hidden Buttons register with the system keyboard shortcut HUD
        // and the responder chain without rendering anything visible.
        Group {
            // ⌘R — Rename
            Button(action: onRename) { EmptyView() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(selectedRole == nil)
                .accessibilityLabel("Rename selected role (⌘R)")
                .opacity(0)

            // ⌘D — Duplicate
            Button(action: onDuplicate) { EmptyView() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(selectedRole == nil)
                .accessibilityLabel("Duplicate selected role (⌘D)")
                .opacity(0)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}
