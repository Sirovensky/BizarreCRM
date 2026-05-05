import SwiftUI
import Core
import DesignSystem

// MARK: - SettingsSearchView

/// Top-bar search field for SettingsView. On iPhone it overlays the regular
/// sections with a result list when active. On iPad it renders as a sidebar
/// filter panel in NavigationSplitView.
public struct SettingsSearchView: View {

    @Bindable private var vm: SettingsSearchViewModel
    /// Called when the user taps a result row. The caller handles navigation.
    private let onSelect: (SettingsEntry) -> Void

    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        vm: SettingsSearchViewModel,
        onSelect: @escaping (SettingsEntry) -> Void
    ) {
        self.vm = vm
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            if !vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resultsList
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextField("Search settings", text: $vm.query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel("Search settings")
                .accessibilityIdentifier("settings.searchField")
                .focused($isFieldFocused)

            if vm.isSearching {
                ProgressView()
                    .scaleEffect(0.75)
                    .accessibilityLabel("Searching…")
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
                .accessibilityIdentifier("settings.searchClear")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .padding(.horizontal, BrandSpacing.base)
        .padding(.top, BrandSpacing.sm)
        .padding(.bottom, BrandSpacing.xs)
    }

    // MARK: - Results list

    @ViewBuilder
    private var resultsList: some View {
        if vm.results.isEmpty && !vm.isSearching {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.results) { entry in
                        SettingsSearchResultRow(entry: entry) {
                            onSelect(entry)
                        }
                        Divider()
                            .padding(.leading, BrandSpacing.xxl + BrandSpacing.base)
                    }
                }
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.snappy),
                    value: vm.results.map(\.id)
                )
            }
            .accessibilityIdentifier("settings.searchResults")
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No settings found for \"\(vm.query)\"")
                .font(.subheadline)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No settings found for \(vm.query)")
        .accessibilityIdentifier("settings.searchEmpty")
    }
}

// MARK: - SettingsSearchResultRow

private struct SettingsSearchResultRow: View {
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
        .accessibilityLabel("\(entry.title), \(entry.breadcrumbDisplay.isEmpty ? "Settings" : "Settings, \(entry.breadcrumbDisplay)")")
        .accessibilityHint("Navigate to \(entry.title)")
        .accessibilityIdentifier("settings.result.\(entry.id)")
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }
}

// MARK: - iPad sidebar variant

/// Compact sidebar filter panel used on iPad NavigationSplitView.
/// Renders the search field + results in a narrower column.
public struct SettingsSearchSidebarView: View {
    @Bindable public var vm: SettingsSearchViewModel
    public let onSelect: (SettingsEntry) -> Void

    public init(vm: SettingsSearchViewModel, onSelect: @escaping (SettingsEntry) -> Void) {
        self.vm = vm
        self.onSelect = onSelect
    }

    public var body: some View {
        SettingsSearchView(vm: vm, onSelect: onSelect)
    }
}
