import SwiftUI
import Core
import DesignSystem

// MARK: - SmsKeyboardShortcuts

/// Applies iPad keyboard shortcuts to any SMS view via a ViewModifier.
///
/// Shortcuts:
///   ⌘N   — new thread (show compose sheet)
///   ⌘F   — focus search field
///   ⌘K   — quick-compose popover (pre-filled phone picker)
///
/// Usage:
/// ```swift
/// someView
///     .modifier(SmsKeyboardShortcuts(
///         onNewThread: { showCompose = true },
///         onSearch:    { isSearching = true },
///         onQuickCompose: { showQuickCompose = true }
///     ))
/// ```
public struct SmsKeyboardShortcuts: ViewModifier {
    public let onNewThread: () -> Void
    public let onSearch: () -> Void
    public let onQuickCompose: () -> Void

    public init(
        onNewThread: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onQuickCompose: @escaping () -> Void
    ) {
        self.onNewThread = onNewThread
        self.onSearch = onSearch
        self.onQuickCompose = onQuickCompose
    }

    public func body(content: Content) -> some View {
        content
            .background(
                // KeyboardShortcut handlers must be on a focusable view; a hidden
                // button is the conventional SwiftUI pattern.
                Group {
                    newThreadButton
                    searchButton
                    quickComposeButton
                }
            )
    }

    // MARK: - ⌘N — New Thread

    private var newThreadButton: some View {
        Button(action: onNewThread) {
            EmptyView()
        }
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("New SMS thread")
        .accessibilityHint("Command N")
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - ⌘F — Focus Search

    private var searchButton: some View {
        Button(action: onSearch) {
            EmptyView()
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel("Search conversations")
        .accessibilityHint("Command F")
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - ⌘K — Quick Compose

    private var quickComposeButton: some View {
        Button(action: onQuickCompose) {
            EmptyView()
        }
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Quick compose")
        .accessibilityHint("Command K")
        .opacity(0)
        .allowsHitTesting(false)
    }
}

// MARK: - View extension

public extension View {
    /// Attaches iPad SMS keyboard shortcuts to this view.
    func smsKeyboardShortcuts(
        onNewThread: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onQuickCompose: @escaping () -> Void
    ) -> some View {
        modifier(SmsKeyboardShortcuts(
            onNewThread: onNewThread,
            onSearch: onSearch,
            onQuickCompose: onQuickCompose
        ))
    }
}

// MARK: - SmsShortcutHelpView

/// Optional overlay that lists available shortcuts.
/// Surface via ⌘/ or via the Help menu.
public struct SmsShortcutHelpView: View {
    private let shortcuts: [(key: String, description: String)] = [
        ("⌘N", "New thread"),
        ("⌘F", "Search conversations"),
        ("⌘K", "Quick compose"),
        ("⌘⇧T", "Message templates"),
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Keyboard Shortcuts")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.bottom, BrandSpacing.xs)

            ForEach(shortcuts, id: \.key) { item in
                HStack {
                    Text(item.key)
                        .font(.brandMono(size: 14))
                        .foregroundStyle(.bizarreOrange)
                        .frame(minWidth: 48, alignment: .leading)
                    Text(item.description)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .padding(BrandSpacing.lg)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding(BrandSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts reference")
    }
}
