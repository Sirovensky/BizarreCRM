import SwiftUI
import Core
import DesignSystem

// MARK: - CommandPaletteView

/// The Command Palette overlay / sheet.
///
/// Layout:
/// - iPhone: full-screen sheet, search field at top, `List` of results.
/// - iPad / Mac: centered overlay, max-width 600 pt, glass material background.
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

    private var iPadLayout: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.sm)

            Divider()
                .padding(.horizontal, BrandSpacing.sm)

            entitySuggestionRow

            resultList
                .frame(maxHeight: 420)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 600)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding(BrandSpacing.xxl)
        .keyboardShortcuts
        // Tap outside overlay to dismiss
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { vm.dismiss() }
                .ignoresSafeArea()
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

    // MARK: - Result list

    private var resultList: some View {
        List {
            ForEach(Array(vm.filteredResults.enumerated()), id: \.element.id) { index, action in
                resultRow(action: action, index: index)
            }
        }
        .listStyle(.plain)
        .animation(reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick), value: vm.filteredResults.map { $0.id })
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

    private func tapAction(at index: Int) {
        vm.select(index: index)
        vm.executeSelected()
    }
}

// MARK: - ActionRow

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
// thin actor holds a weak reference and is set by `CommandPaletteView`
// on appear.

@MainActor
final class CommandPaletteKeyboardRouter {
    static let shared = CommandPaletteKeyboardRouter()
    weak var viewModel: CommandPaletteViewModel?

    func setViewModel(_ vm: CommandPaletteViewModel) { viewModel = vm }
    func moveUp()          { viewModel?.moveSelectionUp() }
    func moveDown()        { viewModel?.moveSelectionDown() }
    func execute()         { viewModel?.executeSelected() }
    func dismissPalette()  { viewModel?.dismiss() }
}

// MARK: - CommandPaletteView + Router wiring

private extension View {
    func wireKeyboardRouter(_ vm: CommandPaletteViewModel) -> some View {
        self.onAppear { CommandPaletteKeyboardRouter.shared.setViewModel(vm) }
    }
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
