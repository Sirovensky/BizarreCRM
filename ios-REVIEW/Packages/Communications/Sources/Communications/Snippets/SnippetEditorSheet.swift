import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SnippetEditorSheet

/// Sheet for creating or editing a snippet.
/// Presents as `.large` detent on iPhone; on iPad it floats as a modal form.
public struct SnippetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SnippetEditorViewModel

    public init(
        snippet: Snippet? = nil,
        api: APIClient,
        onSave: @escaping (Snippet) -> Void
    ) {
        _vm = State(wrappedValue: SnippetEditorViewModel(
            snippet: snippet,
            api: api,
            onSave: onSave
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    shortcodeSection
                    titleSection
                    categorySection
                    contentSection
                    variableInserterSection
                    previewSection
                    if let err = vm.errorMessage {
                        Section {
                            Text(err)
                                .foregroundStyle(.bizarreError)
                                .accessibilityLabel("Error: \(err)")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.isNewSnippet ? "New Snippet" : "Edit Snippet")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel editing snippet")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task { await vm.save() }
                    }
                    .disabled(!vm.isValid || vm.isSaving)
                    .accessibilityLabel(vm.isSaving ? "Saving snippet" : "Save snippet")
                }
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Sections

    private var shortcodeSection: some View {
        Section {
            TextField("e.g. ty-visit", text: $vm.shortcode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.brandMono(size: 15))
                .accessibilityLabel("Shortcode — required, letters digits underscore dash, max 50 chars")

            if !vm.shortcode.isEmpty {
                Text("Type /\(vm.shortcode.trimmingCharacters(in: .whitespaces)) in the SMS composer to insert this snippet")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        } header: {
            Text("Shortcode")
        } footer: {
            Text("Letters, digits, underscore or dash only. Max 50 characters.")
                .font(.brandLabelSmall())
        }
    }

    private var titleSection: some View {
        Section("Title") {
            TextField("Snippet name", text: $vm.title)
                .accessibilityLabel("Snippet title — required, max 200 chars")
        }
    }

    private var categorySection: some View {
        Section("Category (optional)") {
            TextField("e.g. greeting, follow-up", text: $vm.category)
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Snippet category — optional")
        }
    }

    private var contentSection: some View {
        Section("Content") {
            TextEditor(text: $vm.content)
                .frame(minHeight: 110)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Snippet content — required, max 10000 chars")

            HStack {
                Spacer()
                Text("\(vm.content.count) / 10 000")
                    .font(.brandLabelSmall())
                    .foregroundStyle(vm.content.count > 9_500 ? .bizarreError : .bizarreOnSurfaceMuted)
                    .accessibilityLabel("Character count: \(vm.content.count) of 10000")
            }
        }
    }

    private var variableInserterSection: some View {
        Section("Insert variable") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(SnippetEditorViewModel.knownVariables, id: \.self) { variable in
                        Button {
                            vm.content += variable
                        } label: {
                            Text(variable)
                                .font(.brandMono(size: 12))
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, BrandSpacing.xs)
                                .foregroundStyle(.bizarreOnSurface)
                                .background(Color.bizarreSurface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Insert variable \(variable)")
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
            .listRowInsets(EdgeInsets(
                top: 0, leading: BrandSpacing.md,
                bottom: 0, trailing: BrandSpacing.md
            ))
        }
    }

    private var previewSection: some View {
        Section("Preview (sample data)") {
            Text(vm.livePreview.isEmpty ? vm.content : vm.livePreview)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("Snippet preview: \(vm.livePreview)")
        }
    }
}
