import SwiftUI
import DesignSystem

// MARK: - KeyboardShortcutOverlayView

/// Full-screen glass cheat-sheet listing every shortcut grouped by section.
///
/// **Invocation:** shown when the user presses ⌘/ anywhere in the app.
/// The trigger lives in `MainShellView` via a hidden `Button` + `.keyboardShortcut`.
///
/// **Layout:**
/// - iPad: 3-column `LazyVGrid` per group.
/// - iPhone (or compact width): single-column `List`.
///
/// **A11y:** each group heading has `.accessibilityAddTraits(.isHeader)`;
/// each row label reads "Cmd+N — New Ticket" via `accessibilityLabel`.
///
/// **Reduce Motion:** overlay fade only (no slide transform).
public struct KeyboardShortcutOverlayView: View {

    public var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Layout constants

    private static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: BrandSpacing.base), count: 3)
    private static let singleColumn = [GridItem(.flexible())]

    // MARK: - Body

    public init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background dismiss tap target.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)

            // Glass card.
            overlayCard
                .padding(isWide ? BrandSpacing.xxl : BrandSpacing.lg)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard Shortcuts")
    }

    // MARK: - Private helpers

    private var isWide: Bool {
        hSizeClass == .regular
    }

    private var overlayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, BrandSpacing.base)
            shortcutContent
        }
        .frame(maxWidth: isWide ? 900 : .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        HStack {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss shortcuts overlay")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(BrandSpacing.base)
    }

    @ViewBuilder
    private var shortcutContent: some View {
        if isWide {
            ipadContent
        } else {
            iphoneContent
        }
    }

    // MARK: iPad — 3-column grid

    private var ipadContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BrandSpacing.xl) {
                ForEach(KeyboardShortcutCatalog.populatedGroups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        groupHeader(group)
                        LazyVGrid(
                            columns: Self.gridColumns,
                            alignment: .leading,
                            spacing: BrandSpacing.sm
                        ) {
                            ForEach(KeyboardShortcutCatalog.shortcuts(in: group)) { shortcut in
                                ShortcutRow(shortcut: shortcut)
                            }
                        }
                    }
                }
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: iPhone — single-column list

    private var iphoneContent: some View {
        List {
            ForEach(KeyboardShortcutCatalog.populatedGroups, id: \.self) { group in
                Section {
                    ForEach(KeyboardShortcutCatalog.shortcuts(in: group)) { shortcut in
                        ShortcutRow(shortcut: shortcut)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Group header

    private func groupHeader(_ group: ShortcutGroup) -> some View {
        Label(group.displayTitle, systemImage: group.systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - ShortcutRow

private struct ShortcutRow: View {
    let shortcut: AppKeyboardShortcut

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(shortcut.displayLabel)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, BrandSpacing.xs)
                .padding(.vertical, BrandSpacing.xxs)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .minimumScaleFactor(0.8)

            Text(shortcut.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shortcut.accessibilityLabel)
    }
}
