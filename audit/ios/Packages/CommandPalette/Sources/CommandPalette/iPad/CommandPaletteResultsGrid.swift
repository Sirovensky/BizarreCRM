import SwiftUI
import DesignSystem

// MARK: - CommandPaletteResultsGrid

/// iPad 2-column results grid with hover preview on pointer devices.
///
/// Each cell expands to show a short description (derived from keywords)
/// on pointer hover — this makes the palette feel native on iPadOS 17+
/// where pointer support is first-class.
///
/// Usage:
/// ```swift
/// CommandPaletteResultsGrid(
///     results: vm.filteredResults,
///     selectedIndex: vm.selectedIndex,
///     onTap: { index in ... },
///     onHover: { index in ... }
/// )
/// ```
public struct CommandPaletteResultsGrid: View {

    // MARK: - Input

    public let results: [CommandAction]
    public let selectedIndex: Int?
    public let onTap: (Int) -> Void
    public let onHover: (Int?) -> Void

    // MARK: - Init

    public init(
        results: [CommandAction],
        selectedIndex: Int?,
        onTap: @escaping (Int) -> Void,
        onHover: @escaping (Int?) -> Void
    ) {
        self.results = results
        self.selectedIndex = selectedIndex
        self.onTap = onTap
        self.onHover = onHover
    }

    // MARK: - Private state

    @State private var hoveredIndex: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Layout

    private let columns = [
        GridItem(.flexible(), spacing: BrandSpacing.sm),
        GridItem(.flexible(), spacing: BrandSpacing.sm)
    ]

    // MARK: - Body

    public var body: some View {
        Group {
            if results.isEmpty {
                emptyState
            } else {
                resultGrid
            }
        }
    }

    // MARK: - Grid

    private var resultGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, action in
                        ResultGridCell(
                            action: action,
                            isSelected: selectedIndex == index,
                            isHovered: hoveredIndex == index,
                            onTap: { onTap(index) },
                            onHoverChange: { isHovering in
                                hoveredIndex = isHovering ? index : nil
                                onHover(isHovering ? index : nil)
                            }
                        )
                        .id(action.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(action.title)
                        .accessibilityHint(cellAccessibilityHint(action))
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
            }
            .scrollIndicators(.hidden)
            .animation(
                reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick),
                value: results.map { $0.id }
            )
            // Auto-scroll selected cell into view when navigating by keyboard
            .onChange(of: selectedIndex) { _, newIndex in
                guard let newIndex, newIndex < results.count else { return }
                withAnimation(reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick)) {
                    proxy.scrollTo(results[newIndex].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("No results")
                .font(.brandBodyLarge())
                .foregroundStyle(.secondary)

            Text("Try a different search term")
                .font(.brandBodyMedium())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results. Try a different search term.")
    }

    // MARK: - Helpers

    private func cellAccessibilityHint(_ action: CommandAction) -> String {
        let keywords = action.keywords.prefix(3).joined(separator: ", ")
        let extra = keywords.isEmpty ? "" : ". Also known as: \(keywords)"
        return "Double tap to execute\(extra)"
    }
}

// MARK: - ResultGridCell

/// Individual cell in the 2-column grid.
///
/// On pointer hover the cell expands a secondary line showing the first 3
/// keywords as a soft hint. Uses `.hoverEffect(.highlight)` for the native
/// iPadOS pointer interaction, plus a manual `onContinuousHover` tracker
/// to drive the preview expansion.
struct ResultGridCell: View {

    let action: CommandAction
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived

    private var effectivelyHighlighted: Bool { isSelected || isHovered }

    private var previewKeywords: String {
        action.keywords.prefix(3).joined(separator: " · ")
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack(spacing: BrandSpacing.sm) {
                    // Icon
                    Image(systemName: action.icon)
                        .font(.brandTitleMedium())
                        .frame(
                            width: DesignTokens.Touch.minTargetSide,
                            height: DesignTokens.Touch.minTargetSide,
                            alignment: .center
                        )
                        .foregroundStyle(effectivelyHighlighted ? Color.bizarreOrange : Color.primary)
                        .accessibilityHidden(true)

                    // Title
                    Text(action.title)
                        .font(.brandBodyMedium())
                        .foregroundStyle(effectivelyHighlighted ? Color.bizarreOrange : Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    // Return-key indicator when selected
                    if isSelected {
                        Image(systemName: "return")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }

                // Hover preview: keyword hints
                if isHovered && !previewKeywords.isEmpty {
                    Text(previewKeywords)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, DesignTokens.Touch.minTargetSide + BrandSpacing.sm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Touch.minTargetSide, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(effectivelyHighlighted ? Color.bizarreOrange.opacity(0.13) : Color.primary.opacity(0.04))
        )
        .overlay(cellBorder)
        .hoverEffect(.highlight)
        .onContinuousHover { phase in
            let entering: Bool
            switch phase {
            case .active:  entering = true
            case .ended:   entering = false
            }
            withAnimation(reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick)) {
                onHoverChange(entering)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .animation(
            reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick),
            value: effectivelyHighlighted
        )
        .animation(
            reduceMotion ? .none : .smooth(duration: DesignTokens.Motion.quick),
            value: isHovered
        )
    }

    // MARK: - Background & border

    @ViewBuilder
    private var cellBackground: some View {
        if effectivelyHighlighted {
            Color.bizarreOrange.opacity(0.13)
        } else {
            Color.primary.opacity(0.04)
        }
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            .strokeBorder(
                effectivelyHighlighted ? Color.bizarreOrange.opacity(0.45) : Color.clear,
                lineWidth: 1
            )
    }
}

// MARK: - Preview

#if DEBUG
struct CommandPaletteResultsGrid_Previews: PreviewProvider {
    static let actions = CommandCatalog.defaultActions()

    static var previews: some View {
        CommandPaletteResultsGrid(
            results: actions,
            selectedIndex: 2,
            onTap: { _ in },
            onHover: { _ in }
        )
        .frame(width: 512, height: 380)
        .previewDisplayName("Results Grid — iPad")
    }
}
#endif
