import SwiftUI
import Core
import DesignSystem

// MARK: - CommandPaletteView

/// The Command Palette overlay / sheet.
///
/// Layout:
/// - iPhone: full-screen sheet, search field at top, `List` of results (vertical, compact).
/// - iPad / Mac: centered floating overlay, max-width 600 pt, glass chrome,
///   results in a 2-column `LazyVGrid` that shows more at a glance.
///
/// Wire ⌘K / pull-down gesture in RootView; this view is purely presentational.
public struct CommandPaletteView: View {
    @Bindable private var vm: CommandPaletteViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: CommandPaletteViewModel) {
        self.vm = viewModel
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .onChange(of: vm.isDismissed) { _, dismissed in
            if dismissed { dismiss() }
        }
        // Wire keyboard router once the view is on screen
        .onAppear { CommandPaletteKeyboardRouter.shared.setViewModel(vm) }
        .onDisappear { CommandPaletteKeyboardRouter.shared.setViewModel(nil) }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                    .brandGlass(.regular, in: Rectangle())

                Divider()

                entitySuggestionRow

                resultList
            }
            .navigationTitle("Command Palette")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.dismiss() }
                        .accessibilityLabel("Dismiss command palette")
                }
            }
        }
        .keyboardShortcuts
    }

    // MARK: - iPad layout
    //
    // iPad shows a floating glass panel with a 2-column grid of results so
    // more actions are visible without scrolling. The wider viewport and
    // pointer environment justify the richer layout (per CLAUDE.md).

    private var iPadLayout: some View {
        VStack(spacing: 0) {
            // Glass chrome header (search field)
            HStack(spacing: 0) {
                searchField
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.sm)
            .brandGlass(.regular, in: Rectangle())

            Divider()
                .padding(.horizontal, BrandSpacing.sm)

            entitySuggestionRow

            iPadResultGrid
                .frame(maxHeight: 480)

            Spacer(minLength: 0)

            // Footer hint bar
            iPadKeyboardHint
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.xs)
        }
        .frame(maxWidth: 640)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .shadow(
            color: .black.opacity(DesignTokens.Shadows.lg.opacityDark),
            radius: DesignTokens.Shadows.lg.blur,
            y: DesignTokens.Shadows.lg.y
        )
        .padding(BrandSpacing.xxl)
        .keyboardShortcuts
        // Tap outside overlay to dismiss
        .background(
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { vm.dismiss() }
        )
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search actions…", text: $vm.query)
                .font(.brandBodyLarge())
                .submitLabel(.done)
                .onSubmit { vm.executeSelected() }
                .accessibilityLabel("Search command palette")
                .accessibilityHint("Type to filter actions. Use arrow keys to navigate.")

            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Entity suggestion banner

    @ViewBuilder
    private var entitySuggestionRow: some View {
        if let suggestion = vm.entitySuggestion {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: entitySuggestionIcon(suggestion))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(entitySuggestionLabel(suggestion))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xs)
            .background(Color.bizarreOrangeContainer.opacity(0.15))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(entitySuggestionLabel(suggestion))
            .accessibilityHint("Tap to navigate")
        }
    }

    private func entitySuggestionIcon(_ s: EntitySuggestion) -> String {
        switch s {
        case .ticket:  return "ticket"
        case .phone:   return "phone.fill"
        case .sku:     return "barcode"
        }
    }

    private func entitySuggestionLabel(_ s: EntitySuggestion) -> String {
        switch s {
        case .ticket(let id):  return "Go to ticket #\(id)"
        case .phone(let n):    return "Find customer with phone \(n)"
        case .sku(let v):      return "Look up part \(v)"
        }
    }

    // MARK: - iPhone result list (compact vertical, grouped)

    private var resultList: some View {
        Group {
            if vm.filteredResults.isEmpty && !vm.query.isEmpty {
                noResultsEmptyState
            } else if vm.filteredResults.isEmpty {
                promptEmptyState
            } else {
                groupedResultList
            }
        }
        .animation(reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick), value: vm.filteredResults.map { $0.id })
    }

    // Empty state when query is non-empty but nothing matched
    private var noResultsEmptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(verbatim: "No results for \u{201C}\(vm.query)\u{201D}")
                .font(.brandBodyLarge())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Try a different spelling, or use a ticket #, phone number, or SKU.")
                .font(.brandBodyMedium())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results for \(vm.query). Try a different spelling, or use a ticket number, phone number, or SKU.")
    }

    // Empty state shown before the user types anything (no actions registered yet)
    private var promptEmptyState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "keyboard")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Type to search actions")
                .font(.brandBodyLarge())
                .foregroundStyle(.secondary)
        }
        .padding(BrandSpacing.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Type to search actions")
    }

    private var groupedResultList: some View {
        // Build a flat index offset table so we can map section+row → flat index
        let sections = vm.groupedResults
        // If groupedResults not yet populated (shouldn't happen), fall back to ungrouped
        if sections.isEmpty {
            return AnyView(ungroupedResultList)
        }
        return AnyView(
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(Array(section.actions.enumerated()), id: \.element.id) { localIndex, action in
                            let flatIndex = flatIndex(for: action)
                            resultRow(action: action, index: flatIndex)
                        }
                    } header: {
                        Text(section.title)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .animation(reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick), value: vm.filteredResults.map { $0.id })
        )
    }

    // Fallback ungrouped list (used if groupedResults is empty for any reason)
    private var ungroupedResultList: some View {
        List {
            ForEach(Array(vm.filteredResults.enumerated()), id: \.element.id) { index, action in
                resultRow(action: action, index: index)
            }
        }
        .listStyle(.plain)
    }

    /// Returns the flat index of `action` within `vm.filteredResults`.
    private func flatIndex(for action: CommandAction) -> Int {
        vm.filteredResults.firstIndex(where: { $0.id == action.id }) ?? 0
    }

    private func resultRow(action: CommandAction, index: Int) -> some View {
        let isSelected = vm.selectedIndex == index
        return ActionRow(action: action, isSelected: isSelected)
            .listRowBackground(isSelected ? Color.bizarreOrange.opacity(0.15) : Color.clear)
            .listRowSeparator(.hidden)
            .contentShape(Rectangle())
            .onTapGesture { tapAction(at: index) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(action.title)
            .accessibilityHint("Double tap to execute")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - iPad 2-column result grid (spacious, pointer-friendly)

    private let iPadColumns = [
        GridItem(.flexible(), spacing: BrandSpacing.sm),
        GridItem(.flexible(), spacing: BrandSpacing.sm)
    ]

    private var iPadResultGrid: some View {
        Group {
            if vm.filteredResults.isEmpty && !vm.query.isEmpty {
                // No results empty state for iPad overlay
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(verbatim: "No results for \u{201C}\(vm.query)\u{201D}")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(BrandSpacing.xl)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No results for \(vm.query)")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        if vm.groupedResults.isEmpty {
                            // Fallback: ungrouped grid
                            LazyVGrid(columns: iPadColumns, spacing: BrandSpacing.sm) {
                                ForEach(Array(vm.filteredResults.enumerated()), id: \.element.id) { index, action in
                                    iPadActionCell(action: action, index: index)
                                }
                            }
                            .padding(.horizontal, BrandSpacing.base)
                            .padding(.vertical, BrandSpacing.sm)
                        } else {
                            ForEach(vm.groupedResults) { section in
                                Section {
                                    LazyVGrid(columns: iPadColumns, spacing: BrandSpacing.sm) {
                                        ForEach(section.actions, id: \.id) { action in
                                            let idx = flatIndex(for: action)
                                            iPadActionCell(action: action, index: idx)
                                        }
                                    }
                                    .padding(.horizontal, BrandSpacing.base)
                                    .padding(.bottom, BrandSpacing.sm)
                                } header: {
                                    Text(section.title)
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
                                        .padding(.horizontal, BrandSpacing.base)
                                        .padding(.top, BrandSpacing.sm)
                                        .padding(.bottom, BrandSpacing.xs)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.ultraThinMaterial)
                                }
                            }
                        }
                    }
                }
                .animation(reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick), value: vm.filteredResults.map { $0.id })
                .scrollIndicators(.hidden)
            }
        }
    }

    private func iPadActionCell(action: CommandAction, index: Int) -> some View {
        let isSelected = vm.selectedIndex == index
        return ActionGridCell(action: action, isSelected: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .onTapGesture { tapAction(at: index) }
            .hoverEffect(.highlight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(action.title)
            .accessibilityHint("Double tap to execute")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - iPad keyboard hint footer

    private var iPadKeyboardHint: some View {
        HStack(spacing: BrandSpacing.base) {
            keyHintChip(symbol: "arrow.up", label: "↑")
            keyHintChip(symbol: "arrow.down", label: "↓")
            Text("Navigate")
                .font(.brandLabelSmall())
                .foregroundStyle(.tertiary)
            Spacer()
            keyHintChip(symbol: "return", label: "↵")
            Text("Execute")
                .font(.brandLabelSmall())
                .foregroundStyle(.tertiary)
            Spacer()
            keyHintChip(symbol: "escape", label: "Esc")
            Text("Dismiss")
                .font(.brandLabelSmall())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private func keyHintChip(symbol: String, label: String) -> some View {
        Text(label)
            .font(.brandMono(size: 11))
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            .accessibilityHidden(true)
    }

    // MARK: - Shared helpers

    private func tapAction(at index: Int) {
        vm.select(index: index)
        vm.executeSelected()
    }
}

// MARK: - ActionRow (iPhone list row)

private struct ActionRow: View {
    let action: CommandAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: action.icon)
                .font(.brandTitleMedium())
                .frame(width: DesignTokens.Touch.minTargetSide, alignment: .center)
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.primary)
                .accessibilityHidden(true)

            Text(action.title)
                .font(.brandBodyLarge())
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.primary)

            Spacer()

            // Keyboard shortcut hint (shown when not selected to avoid overlap with ↵)
            if !isSelected, let hint = action.shortcutHint {
                Text(hint.displayString)
                    .font(.brandMono(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, BrandSpacing.xs)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .accessibilityHidden(true)
            }

            if isSelected {
                Image(systemName: "return")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - ActionGridCell (iPad 2-column grid cell)

private struct ActionGridCell: View {
    let action: CommandAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: action.icon)
                .font(.brandTitleMedium())
                .frame(width: DesignTokens.Touch.minTargetSide, alignment: .center)
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.primary)
                .accessibilityHidden(true)

            Text(action.title)
                .font(.brandBodyMedium())
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.primary)
                .lineLimit(2)

            Spacer()

            // Keyboard shortcut chip
            if let hint = action.shortcutHint {
                Text(hint.displayString)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, BrandSpacing.xs)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .background(
            isSelected
                ? Color.bizarreOrange.opacity(0.15)
                : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(
                    isSelected ? Color.bizarreOrange.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Keyboard shortcut modifier

private extension View {
    var keyboardShortcuts: some View {
        self
            .onKeyPress(.upArrow) {
                Task { @MainActor in CommandPaletteKeyboardRouter.shared.moveUp() }
                return .handled
            }
            .onKeyPress(.downArrow) {
                Task { @MainActor in CommandPaletteKeyboardRouter.shared.moveDown() }
                return .handled
            }
            .onKeyPress(.return) {
                Task { @MainActor in CommandPaletteKeyboardRouter.shared.execute() }
                return .handled
            }
            .onKeyPress(.escape) {
                Task { @MainActor in CommandPaletteKeyboardRouter.shared.dismissPalette() }
                return .handled
            }
    }
}

// MARK: - Keyboard router (bridges View modifier → ViewModel)
//
// SwiftUI key-press handlers are value-type closures that can't directly
// capture `@Observable` vm without re-initialisation each redraw. This
// thin singleton holds a weak reference set from `.onAppear`.

@MainActor
final class CommandPaletteKeyboardRouter {
    static let shared = CommandPaletteKeyboardRouter()
    weak var viewModel: CommandPaletteViewModel?

    func setViewModel(_ vm: CommandPaletteViewModel?) { viewModel = vm }
    func moveUp()          { viewModel?.moveSelectionUp() }
    func moveDown()        { viewModel?.moveSelectionDown() }
    func execute()         { viewModel?.executeSelected() }
    func dismissPalette()  { viewModel?.dismiss() }
}

// MARK: - Previews

#if DEBUG
struct CommandPaletteView_Previews: PreviewProvider {
    static func makeVM() -> CommandPaletteViewModel {
        CommandPaletteViewModel(
            actions: CommandCatalog.defaultActions(),
            context: .ticket(id: "1234"),
            contextActionBuilder: { context in
                switch context {
                case .ticket(let id):
                    return [
                        CommandAction(
                            id: "ctx-add-note-\(id)",
                            title: "Add note to ticket",
                            icon: "note.text.badge.plus",
                            keywords: ["note", "comment"],
                            handler: {}
                        ),
                        CommandAction(
                            id: "ctx-sms-\(id)",
                            title: "SMS this customer",
                            icon: "message.fill",
                            keywords: ["text", "message"],
                            handler: {}
                        )
                    ]
                default:
                    return []
                }
            }
        )
    }

    static var previews: some View {
        Group {
            CommandPaletteView(viewModel: makeVM())
                .previewDisplayName("iPhone")
                .previewDevice("iPhone 16 Pro")

            CommandPaletteView(viewModel: makeVM())
                .previewDisplayName("iPad")
                .previewDevice("iPad Pro 13-inch (M4)")
        }
    }
}
#endif
