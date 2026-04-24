import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SnippetPickerSheet

/// Reusable picker that embeds `SnippetsListView` in picker mode.
/// Dismiss is handled automatically when the user taps a snippet (via `onPick`).
///
/// Usage from SMS composer:
/// ```swift
/// .sheet(isPresented: $showSnippetPicker) {
///     SnippetPickerSheet(api: api) { snippet in
///         composeBody += snippet.content
///         showSnippetPicker = false
///     }
/// }
/// ```
public struct SnippetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let onPick: (Snippet) -> Void

    public init(api: APIClient, onPick: @escaping (Snippet) -> Void) {
        self.api = api
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            SnippetsListView(api: api) { snippet in
                onPick(snippet)
                dismiss()
            }
            .navigationTitle("Choose Snippet")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel snippet picker")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.visible)
    }
}
