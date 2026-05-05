#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// §5.9 — Multi-select tag editor sheet with server-side autosuggest.

public struct CustomerTagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerTagEditorViewModel
    private let onSaved: ([String]) -> Void

    public init(api: APIClient, customerId: Int64, initialTags: [String], onSaved: @escaping ([String]) -> Void = { _ in }) {
        _vm = State(wrappedValue: CustomerTagEditorViewModel(api: api, customerId: customerId, initialTags: initialTags))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    selectedTagsSection
                    searchSection
                    if !vm.suggestions.isEmpty {
                        suggestionsSection
                    }
                    warningIfAtLimit
                }
                .padding(BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Edit tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task {
                            await vm.save()
                            if vm.savedSuccessfully {
                                onSaved(vm.selectedTags)
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Selected chips

    private var selectedTagsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Current tags (\(vm.selectedTags.count) / 20)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            if vm.selectedTags.isEmpty {
                Text("No tags yet. Search or type below to add.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                FlowTagChips(tags: vm.selectedTags) { tag in
                    vm.removeTag(tag)
                }
            }

            if let err = vm.saveError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        }
    }

    // MARK: - Search field

    private var searchSection: some View {
        HStack(spacing: BrandSpacing.sm) {
            TextField("Add tag…", text: $vm.query)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Tag search or new tag entry")
                .onSubmit {
                    vm.addQueryAsTag()
                }
            if !vm.query.isEmpty {
                Button {
                    vm.addQueryAsTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .font(.system(size: 22))
                }
                .accessibilityLabel("Add tag \(vm.query)")
            }
            if vm.isSuggesting {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Suggestions")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            FlowTagChips(tags: vm.suggestions, isAddStyle: true) { tag in
                vm.toggleTag(tag)
            }
        }
    }

    @ViewBuilder
    private var warningIfAtLimit: some View {
        if vm.selectedTags.count >= 20 {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreWarning)
                    .font(.system(size: 14))
                Text("Maximum 20 tags reached.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }
        } else if vm.selectedTags.count >= 10 {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.bizarreTeal)
                    .font(.system(size: 14))
                Text("\(vm.selectedTags.count) of 20 tags used.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
    }
}

// MARK: - FlowTagChips

/// Horizontally-wrapping chip list. Uses a simple LazyVGrid with adaptive columns.
/// `isAddStyle` renders chips as "+ tag" (suggestions); otherwise renders as "tag ×".
private struct FlowTagChips: View {
    let tags: [String]
    var isAddStyle: Bool = false
    let onTap: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 60), spacing: BrandSpacing.xs)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onTap(tag)
                } label: {
                    HStack(spacing: 4) {
                        if isAddStyle {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(tag)
                            .font(.brandLabelLarge())
                            .lineLimit(1)
                        if !isAddStyle {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .foregroundStyle(isAddStyle ? .bizarreTeal : .bizarreOnSurface)
                    .background(
                        isAddStyle ? Color.bizarreTeal.opacity(0.12) : Color.bizarreSurface2,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAddStyle ? "Add tag \(tag)" : "Remove tag \(tag)")
            }
        }
    }
}
#endif
