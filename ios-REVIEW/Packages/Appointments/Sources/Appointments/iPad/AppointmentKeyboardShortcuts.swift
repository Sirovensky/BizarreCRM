import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentKeyboardShortcuts
//
// Keyboard-shortcut overlay for iPad Appointments screens.
//
// Registered shortcuts:
//   ⌘N   → New appointment  (triggers onNew callback)
//   ⌘T   → Jump to today    (triggers onToday callback)
//   ⌘F   → Find / search    (triggers onFind callback)
//   ⌘R   → Refresh          (triggers onRefresh callback)
//
// Usage:
//   someView
//       .appointmentKeyboardShortcuts(
//           onNew: { showCreate = true },
//           onToday: { vm.goToToday() },
//           onFind: { showSearch = true },
//           onRefresh: { Task { await vm.refresh() } }
//       )
//
// The modifier attaches invisible zero-size buttons that carry the
// `.keyboardShortcut` modifier — the standard SwiftUI pattern for
// app-wide shortcuts that don't belong on a specific visible button.

// MARK: - ViewModifier

public struct AppointmentKeyboardShortcutsModifier: ViewModifier {

    public let onNew: () -> Void
    public let onToday: () -> Void
    public let onFind: () -> Void
    public let onRefresh: () -> Void

    public func body(content: Content) -> some View {
        content
            .background(shortcutButtons)
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        // Each Button is zero-size; SwiftUI still registers the shortcut.
        ZStack {
            // ⌘N — New appointment
            Button(action: onNew) {
                EmptyView()
            }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("New appointment")
            .frame(width: 0, height: 0)

            // ⌘T — Today
            Button(action: onToday) {
                EmptyView()
            }
            .keyboardShortcut("t", modifiers: .command)
            .accessibilityLabel("Go to today")
            .frame(width: 0, height: 0)

            // ⌘F — Find / Search
            Button(action: onFind) {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Search appointments")
            .frame(width: 0, height: 0)

            // ⌘R — Refresh
            Button(action: onRefresh) {
                EmptyView()
            }
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Refresh appointments")
            .frame(width: 0, height: 0)
        }
        .allowsHitTesting(false)
        .accessibility(hidden: true)
    }
}

// MARK: - View extension

public extension View {
    /// Attaches Appointments-specific keyboard shortcuts.
    ///
    /// - Parameters:
    ///   - onNew:     Called when ⌘N is pressed. Typically presents the create sheet.
    ///   - onToday:   Called when ⌘T is pressed. Typically scrolls / navigates to today.
    ///   - onFind:    Called when ⌘F is pressed. Typically focuses a search field.
    ///   - onRefresh: Called when ⌘R is pressed. Typically triggers a data reload.
    func appointmentKeyboardShortcuts(
        onNew: @escaping () -> Void,
        onToday: @escaping () -> Void,
        onFind: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) -> some View {
        modifier(AppointmentKeyboardShortcutsModifier(
            onNew: onNew,
            onToday: onToday,
            onFind: onFind,
            onRefresh: onRefresh
        ))
    }
}

// MARK: - AppointmentKeyboardShortcutsDescriptor

/// Static descriptor for displaying a keyboard-shortcut legend in a help popover.
public enum AppointmentKeyboardShortcutsDescriptor {

    public struct ShortcutEntry: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let symbol: String
        public let modifiers: String
        public let key: String
    }

    public static let all: [ShortcutEntry] = [
        ShortcutEntry(id: "new",     label: "New Appointment",  symbol: "plus",               modifiers: "⌘", key: "N"),
        ShortcutEntry(id: "today",   label: "Jump to Today",    symbol: "sun.max",             modifiers: "⌘", key: "T"),
        ShortcutEntry(id: "find",    label: "Find / Search",    symbol: "magnifyingglass",     modifiers: "⌘", key: "F"),
        ShortcutEntry(id: "refresh", label: "Refresh",          symbol: "arrow.clockwise",     modifiers: "⌘", key: "R"),
    ]
}

// MARK: - AppointmentShortcutsHelpView

/// Help popover showing the registered shortcuts.
/// Present from a toolbar "keyboard" button or via ?.
public struct AppointmentShortcutsHelpView: View {

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Keyboard Shortcuts")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.bottom, BrandSpacing.xxs)

            ForEach(AppointmentKeyboardShortcutsDescriptor.all) { entry in
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: entry.symbol)
                        .frame(width: 20)
                        .foregroundStyle(Color.bizarreOrange)
                        .accessibilityHidden(true)
                    Text(entry.label)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text("\(entry.modifiers)\(entry.key)")
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, BrandSpacing.xxs)
                        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.label): \(entry.modifiers)\(entry.key)")
            }
        }
        .padding(BrandSpacing.base)
        .frame(minWidth: 280)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }
}
