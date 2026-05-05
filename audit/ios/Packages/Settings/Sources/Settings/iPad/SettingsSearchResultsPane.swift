import SwiftUI
import DesignSystem

// MARK: - SettingsSearchResultsPane

/// Inline inspector pane (column 2) that surfaces settings search matches on
/// iPad. Appears when the user activates ⌘F or focuses the search field in
/// `SettingsThreeColumnShell`.
///
/// - Shows a search field with Liquid Glass chrome.
/// - Below the field: a scrollable list of `SettingsEntry` matches.
/// - Tapping a row fires `onSelect` so the shell can navigate col-3.
/// - Shows a proper empty state when no results are found.
public struct SettingsSearchResultsPane: View {

    @Bindable var vm: SettingsSearchViewModel

    /// Called when the user taps a result row.
    let onSelect: (SettingsEntry) -> Void

    /// Controls whether the search field is focused (driven by ⌘F).
    @FocusState.Binding var isFieldFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        vm: SettingsSearchViewModel,
        onSelect: @escaping (SettingsEntry) -> Void,
        isFieldFocused: FocusState<Bool>.Binding
    ) {
        self.vm = vm
        self.onSelect = onSelect
        self._isFieldFocused = isFieldFocused
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsArea
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("settings.searchResultsPane")
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextField("Search settings…", text: $vm.query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel("Search settings")
                .accessibilityIdentifier("settings.searchPane.field")
                .focused($isFieldFocused)
                .submitLabel(.search)

            if vm.isSearching {
                ProgressView()
                    .scaleEffect(0.75)
                    .accessibilityLabel("Searching")
            }

            if !vm.query.isEmpty {
                Button {
                    vm.clear()
                    isFieldFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("settings.searchPane.clear")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .padding(BrandSpacing.base)
    }

    // MARK: - Results area

    @ViewBuilder
    private var resultsArea: some View {
        let trimmed = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            promptState
        } else if vm.results.isEmpty && !vm.isSearching {
            emptyState
        } else {
            resultsList
        }
    }

    private var promptState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Type to search all settings")
                .font(.subheadline)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Text("Tip: press ⌘F at any time")
                .font(.caption)
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.7))
        }
        .padding(BrandSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Type to search settings")
        .accessibilityIdentifier("settings.searchPane.prompt")
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No results for \"\(vm.query)\"")
                .font(.subheadline)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results for \(vm.query)")
        .accessibilityIdentifier("settings.searchPane.empty")
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.results) { entry in
                    SearchResultRow(entry: entry) {
                        onSelect(entry)
                        vm.clear()
                        isFieldFocused = false
                    }
                    Divider()
                        .padding(.leading, BrandSpacing.xxl + BrandSpacing.base)
                }
            }
            .padding(.bottom, BrandSpacing.base)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.snappy),
                value: vm.results.map(\.id)
            )
        }
        .accessibilityIdentifier("settings.searchPane.list")
    }
}

// MARK: - SearchResultRow

private struct SearchResultRow: View {
    let entry: SettingsEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.base) {
                Image(systemName: entry.iconSystemName)
                    .frame(width: BrandSpacing.xxl, height: BrandSpacing.xxl)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(entry.title)
                        .font(.body)
                        .foregroundStyle(.bizarreOnSurface)

                    if !entry.breadcrumb.isEmpty {
                        Text("Settings › \(entry.breadcrumbDisplay)")
                            .font(.caption)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm + BrandSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title), \(entry.breadcrumb.isEmpty ? "Settings" : "Settings, \(entry.breadcrumbDisplay)")")
        .accessibilityHint("Navigate to \(entry.title)")
        .accessibilityIdentifier("settings.searchPane.result.\(entry.id)")
        .hoverEffect(.highlight)
    }
}

// MARK: - SettingsSearchResultsPaneWrapper

/// Convenience wrapper for call sites that own `FocusState` locally.
///
/// Use when the parent view owns its own `@FocusState` and just wants to pass
/// the binding without threading `FocusState.Binding` through the init chain.
public struct SettingsSearchResultsPaneWrapper: View {

    @Bindable var vm: SettingsSearchViewModel
    let onSelect: (SettingsEntry) -> Void

    @FocusState private var fieldFocused: Bool

    public init(vm: SettingsSearchViewModel, onSelect: @escaping (SettingsEntry) -> Void) {
        self.vm = vm
        self.onSelect = onSelect
    }

    public var body: some View {
        SettingsSearchResultsPane(
            vm: vm,
            onSelect: onSelect,
            isFieldFocused: $fieldFocused
        )
        .onAppear { fieldFocused = true }
    }
}
