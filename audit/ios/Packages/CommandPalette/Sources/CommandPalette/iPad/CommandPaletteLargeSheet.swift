import SwiftUI
import DesignSystem

// MARK: - CommandPaletteLargeSheet

/// Full iPad ⌘K overlay: 640 × 520 glass panel with a left-rail section
/// sidebar (Recent / Navigation / Actions / Search) and a scrollable
/// right-side results area.
///
/// Layout contract:
/// - Outer frame: 640 wide, 520 tall, centred in a dimmed full-screen backdrop.
/// - Left rail: 128 pt wide, glass chrome, shows 4 section tabs.
/// - Right area: flexible, hosts `CommandPaletteResultsGrid` + hint footer.
/// - Glass: one `BrandGlassContainer` wraps the whole panel so left rail +
///   right chrome share a single sampling region (avoids glass-on-glass).
///
/// This view is purely presentational — the caller supplies a
/// `CommandPaletteViewModel` and observes `vm.isDismissed`.
public struct CommandPaletteLargeSheet: View {

    // MARK: - Public init

    @Bindable public var vm: CommandPaletteViewModel

    /// Active section filter. Selecting a section in the left rail sets this.
    @State private var activeSection: PaletteSection = .all

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: CommandPaletteViewModel) {
        self.vm = viewModel
    }

    // MARK: - Geometry constants

    private let sheetWidth:  CGFloat = 640
    private let sheetHeight: CGFloat = 520
    private let railWidth:   CGFloat = 128

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Dimmed backdrop — tap to dismiss
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { vm.dismiss() }

            // Main glass panel
            BrandGlassContainer(spacing: 0) {
                HStack(spacing: 0) {
                    sectionRail
                    Divider()
                    rightPane
                }
            }
            .frame(width: sheetWidth, height: sheetHeight)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
            .shadow(
                color: .black.opacity(DesignTokens.Shadows.lg.opacityDark),
                radius: DesignTokens.Shadows.lg.blur,
                y: DesignTokens.Shadows.lg.y
            )
        }
        .onChange(of: vm.isDismissed) { _, dismissed in
            if dismissed { dismiss() }
        }
        .onAppear  { CommandPaletteKeyboardRouter.shared.setViewModel(vm) }
        .onDisappear { CommandPaletteKeyboardRouter.shared.setViewModel(nil) }
        .onKeyPress(.upArrow)   { Task { @MainActor in CommandPaletteKeyboardRouter.shared.moveUp() };    return .handled }
        .onKeyPress(.downArrow) { Task { @MainActor in CommandPaletteKeyboardRouter.shared.moveDown() };  return .handled }
        .onKeyPress(.return)    { Task { @MainActor in CommandPaletteKeyboardRouter.shared.execute() };   return .handled }
        .onKeyPress(.escape)    { Task { @MainActor in CommandPaletteKeyboardRouter.shared.dismissPalette() }; return .handled }
    }

    // MARK: - Left rail

    private var sectionRail: some View {
        VStack(spacing: 0) {
            // Mini logo / app icon area
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .padding(.top, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.md)
                .accessibilityHidden(true)

            Divider()
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.bottom, BrandSpacing.sm)

            // Section tabs
            VStack(spacing: BrandSpacing.xs) {
                ForEach(PaletteSection.allCases) { section in
                    sectionTab(section)
                }
            }
            .padding(.horizontal, BrandSpacing.sm)

            Spacer()

            // Dismiss affordance
            Button {
                vm.dismiss()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss command palette")
            .padding(.bottom, BrandSpacing.base)
        }
        .frame(width: railWidth)
        .brandGlass(.clear, in: Rectangle())
    }

    private func sectionTab(_ section: PaletteSection) -> some View {
        let isActive = activeSection == section
        return Button {
            withAnimation(reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick)) {
                activeSection = section
                vm.query = ""
            }
        } label: {
            VStack(spacing: BrandSpacing.xxs) {
                Image(systemName: section.icon)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.bizarreOrange : Color.secondary)
                    .frame(width: DesignTokens.Touch.minTargetSide,
                           height: DesignTokens.Touch.minTargetSide)

                Text(section.label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isActive ? Color.bizarreOrange : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.xs)
            .background(
                isActive
                    ? Color.bizarreOrange.opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            )
        }
        .accessibilityLabel(section.accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Right pane

    private var rightPane: some View {
        VStack(spacing: 0) {
            // Search field
            searchField
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.sm)

            Divider()
                .padding(.horizontal, BrandSpacing.sm)

            // Entity suggestion banner
            entitySuggestionBanner

            // Section header label
            sectionHeaderLabel
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.xs)

            // Results grid
            CommandPaletteResultsGrid(
                results: sectionFilteredResults,
                selectedIndex: vm.selectedIndex,
                onTap: { index in
                    vm.select(index: index)
                    vm.executeSelected()
                },
                onHover: { index in
                    if let i = index { vm.select(index: i) }
                }
            )
            .frame(maxHeight: .infinity)

            Divider()
                .padding(.horizontal, BrandSpacing.sm)

            // Keyboard hint bar
            CommandPaletteKeyboardHintBar()
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.xs)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search \(activeSection.searchPlaceholder)…", text: $vm.query)
                .font(.brandBodyLarge())
                .submitLabel(.done)
                .onSubmit { vm.executeSelected() }
                .accessibilityLabel("Search \(activeSection.accessibilityLabel)")
                .accessibilityHint("Type to filter. Arrow keys navigate. Return executes.")

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
    private var entitySuggestionBanner: some View {
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

    // MARK: - Section header label

    @ViewBuilder
    private var sectionHeaderLabel: some View {
        if activeSection != .all || !vm.query.isEmpty {
            HStack {
                Text(vm.query.isEmpty ? activeSection.label : "Results")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(sectionFilteredResults.count)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Section-filtered results

    /// Apply section filter on top of the VM's fuzzy-ranked results.
    private var sectionFilteredResults: [CommandAction] {
        let base = vm.filteredResults
        switch activeSection {
        case .all:
            return base
        case .recent:
            return base  // VM already ranks recency; top 6 is sufficient
                .prefix(6)
                .map { $0 }
        case .navigation:
            return base.filter { $0.keywords.contains("home") || $0.keywords.contains("overview") || $0.id.hasPrefix("open-") }
        case .actions:
            return base.filter { !$0.id.hasPrefix("open-") && !$0.id.hasPrefix("settings-") && !$0.id.hasPrefix("reports-") }
        case .search:
            return vm.query.isEmpty ? [] : base
        }
    }
}

// MARK: - PaletteSection

/// The left-rail section tabs for the large iPad overlay.
public enum PaletteSection: String, CaseIterable, Identifiable {
    case all        = "all"
    case recent     = "recent"
    case navigation = "navigation"
    case actions    = "actions"
    case search     = "search"

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        return "All"
        case .recent:     return "Recent"
        case .navigation: return "Navigate"
        case .actions:    return "Actions"
        case .search:     return "Search"
        }
    }

    var icon: String {
        switch self {
        case .all:        return "square.grid.2x2"
        case .recent:     return "clock.arrow.circlepath"
        case .navigation: return "arrow.triangle.turn.up.right.diamond"
        case .actions:    return "bolt.fill"
        case .search:     return "magnifyingglass"
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .all:        return "actions"
        case .recent:     return "recent actions"
        case .navigation: return "navigation"
        case .actions:    return "actions"
        case .search:     return "everything"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .all:        return "All actions"
        case .recent:     return "Recent actions"
        case .navigation: return "Navigation actions"
        case .actions:    return "Quick actions"
        case .search:     return "Search"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CommandPaletteLargeSheet_Previews: PreviewProvider {
    static var previews: some View {
        CommandPaletteLargeSheet(
            viewModel: CommandPaletteViewModel(
                actions: CommandCatalog.defaultActions(),
                context: .ticket(id: "2025")
            )
        )
        .previewDevice("iPad Pro 13-inch (M4)")
        .previewDisplayName("iPad Large Sheet")
    }
}
#endif
