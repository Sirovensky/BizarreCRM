import SwiftUI
import Core
import DesignSystem

// MARK: - ThreadSearchView

/// Search within a single SMS thread's messages.
/// Presented as a sheet from the thread view toolbar.
public struct ThreadSearchView: View {
    @State private var vm: ThreadSearchViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// Called when user taps a result to jump to that message.
    public var onSelect: ((Int64) -> Void)?

    public init(vm: ThreadSearchViewModel, onSelect: ((Int64) -> Void)? = nil) {
        _vm = State(wrappedValue: vm)
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    Divider()
                    resultList
                }
            }
            .navigationTitle("Search Messages")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { searchFocused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextField("Search in this conversation", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .focused($searchFocused)
                .autocorrectionDisabled()

            if !vm.query.isEmpty {
                Button {
                    vm.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if vm.isSearching {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultList: some View {
        if vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Type to search messages")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.results.isEmpty && !vm.isSearching {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No results for \"\(vm.query)\"")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.results) { result in
                    Button {
                        onSelect?(result.messageId)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            HighlightedText(text: result.snippet, query: result.query)
                                .font(.brandBodyMedium())
                            if let ts = result.createdAt?.prefix(16) {
                                Text(String(ts).replacingOccurrences(of: "T", with: " "))
                                    .font(.brandMono(size: 11))
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .padding(.vertical, BrandSpacing.xs)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityLabel(result.snippet)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - HighlightedText

/// Renders plain text with occurrences of `query` highlighted in orange.
private struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        buildText()
    }

    private func buildText() -> Text {
        guard !query.isEmpty else { return Text(text).foregroundStyle(.bizarreOnSurface) }
        let lower = text.lowercased()
        let lowQ  = query.lowercased()
        var result = Text("")
        var searchFrom = lower.startIndex

        while let range = lower.range(of: lowQ, range: searchFrom..<lower.endIndex) {
            // Text before match
            let beforeRange = searchFrom..<range.lowerBound
            let beforeStr = String(text[beforeRange])
            if !beforeStr.isEmpty {
                result = result + Text(beforeStr).foregroundColor(.init(.bizarreOnSurface))
            }
            // Matched portion
            let matchStr = String(text[range])
            result = result + Text(matchStr)
                .foregroundColor(.init(.bizarreOrange))
                .fontWeight(.semibold)

            searchFrom = range.upperBound
        }

        // Remaining text
        let tail = String(text[searchFrom...])
        if !tail.isEmpty {
            result = result + Text(tail).foregroundColor(.init(.bizarreOnSurface))
        }
        return result
    }
}
