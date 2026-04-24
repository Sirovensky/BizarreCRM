#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §5 Customer Groups & Tags — TagPicker reusable component
//
// A standalone, reusable tag chooser that can be embedded anywhere.
// Usage:
//   TagPicker(selectedTags: $tags, suggestions: suggestions)
//
// Also ships a TagPickerSheet wrapper for sheet-based presentation.

// MARK: - TagPicker (inline, embeddable)

/// Inline tag input with chip display and suggestion row.
/// Uses immutable binding — does not mutate the passed array directly;
/// it calls the binding setter with a new array on every change.
public struct TagPicker: View {

    @Binding public var selectedTags: [String]
    public var suggestions: [String]
    public var maxTags: Int
    public var placeholder: String
    public var isSuggesting: Bool

    @State private var inputText: String = ""

    public init(
        selectedTags: Binding<[String]>,
        suggestions: [String] = [],
        maxTags: Int = 20,
        placeholder: String = "Add tag…",
        isSuggesting: Bool = false
    ) {
        self._selectedTags = selectedTags
        self.suggestions = suggestions
        self.maxTags = maxTags
        self.placeholder = placeholder
        self.isSuggesting = isSuggesting
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if !selectedTags.isEmpty {
                selectedChips
            }

            inputRow

            if !suggestions.isEmpty {
                suggestionRow
            }

            if selectedTags.count >= maxTags {
                limitWarning
            }
        }
    }

    // MARK: - Selected chips

    private var selectedChips: some View {
        let columns = [GridItem(.adaptive(minimum: 60), spacing: BrandSpacing.xs)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(selectedTags, id: \.self) { tag in
                tagChip(tag: tag, isSelected: true)
            }
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            TextField(placeholder, text: $inputText)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Tag input")
                .onSubmit { commitInput() }

            if !inputText.isEmpty {
                Button {
                    commitInput()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add tag \(inputText)")
            }

            if isSuggesting {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        }
    }

    // MARK: - Suggestion row

    private var suggestionRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Suggestions")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            let columns = [GridItem(.adaptive(minimum: 60), spacing: BrandSpacing.xs)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: BrandSpacing.xs) {
                ForEach(filteredSuggestions, id: \.self) { tag in
                    tagChip(tag: tag, isSelected: false)
                }
            }
        }
    }

    private var filteredSuggestions: [String] {
        suggestions.filter { !selectedTags.contains($0) }
    }

    // MARK: - Limit warning

    private var limitWarning: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreWarning)
                .font(.system(size: 13))
            Text("Maximum \(maxTags) tags reached.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
        }
    }

    // MARK: - Chip builder

    private func tagChip(tag: String, isSelected: Bool) -> some View {
        Button {
            if isSelected {
                removeTag(tag)
            } else {
                addTag(tag)
            }
        } label: {
            HStack(spacing: 4) {
                if !isSelected {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(tag)
                    .font(.brandLabelLarge())
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(isSelected ? .bizarreOnSurface : .bizarreTeal)
            .background(
                isSelected ? Color.bizarreSurface2 : Color.bizarreTeal.opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Remove tag \(tag)" : "Add tag \(tag)")
    }

    // MARK: - Mutations (immutable pattern)

    private func commitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addTag(trimmed)
        inputText = ""
    }

    private func addTag(_ tag: String) {
        guard selectedTags.count < maxTags, !selectedTags.contains(tag) else { return }
        selectedTags = selectedTags + [tag]
    }

    private func removeTag(_ tag: String) {
        selectedTags = selectedTags.filter { $0 != tag }
    }
}

// MARK: - TagPickerSheet (sheet wrapper)

/// Presents `TagPicker` in a sheet with Save/Cancel toolbar buttons.
/// `onSave` receives the final tag array; the sheet dismisses itself.
public struct TagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var workingTags: [String]
    @State private var suggestions: [String]

    private let title: String
    private let onSave: ([String]) -> Void

    public init(
        title: String = "Edit tags",
        initialTags: [String],
        suggestions: [String] = [],
        onSave: @escaping ([String]) -> Void
    ) {
        self.title = title
        self._workingTags = State(wrappedValue: initialTags)
        self._suggestions = State(wrappedValue: suggestions)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.base) {
                    headerLabel
                    TagPicker(selectedTags: $workingTags, suggestions: suggestions)
                }
                .padding(BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(workingTags)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var headerLabel: some View {
        Text("Tags (\(workingTags.count) / 20)")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
    }
}
#endif
