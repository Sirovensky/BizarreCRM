import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.3 Lead tags chip picker

/// Displays existing tags on a `LeadDetail` and opens an editor sheet.
///
/// Tags are rendered as Capsule chips. Tapping the "Edit" button opens
/// `LeadTagEditorSheet` which lets staff add/remove free-form tags.
public struct LeadTagsSection: View {
    public let leadId: Int64
    public let initialTags: [String]
    public let api: APIClient

    @State private var tags: [String]
    @State private var showingEditor: Bool = false

    public init(leadId: Int64, initialTags: [String], api: APIClient) {
        self.leadId = leadId
        self.initialTags = initialTags
        self.api = api
        _tags = State(wrappedValue: initialTags)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("TAGS")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    showingEditor = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Edit tags")
                .hoverEffect(.highlight)
            }

            if tags.isEmpty {
                Text("No tags yet")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                tagChips
            }
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .sheet(isPresented: $showingEditor) {
            LeadTagEditorSheet(api: api, leadId: leadId, initialTags: tags) { updated in
                tags = updated
            }
        }
    }

    private var tagChips: some View {
        let columns = [GridItem(.adaptive(minimum: 60), spacing: BrandSpacing.xs)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreSurface2, in: Capsule())
                    .accessibilityLabel("Tag: \(tag)")
            }
        }
    }
}

// MARK: - LeadTagEditorSheet

/// Sheet for adding/removing tags on a Lead.
/// Max 20 tags (same guard as CustomerTagEditorViewModel).
public struct LeadTagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: LeadTagEditorViewModel
    private let onSaved: ([String]) -> Void

    public init(api: APIClient, leadId: Int64, initialTags: [String], onSaved: @escaping ([String]) -> Void = { _ in }) {
        _vm = State(wrappedValue: LeadTagEditorViewModel(api: api, leadId: leadId, initialTags: initialTags))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    selectedSection
                    entrySection
                    limitWarning
                }
                .padding(BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Lead Tags")
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
                                onSaved(vm.tags)
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Tags (\(vm.tags.count) / 20)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if vm.tags.isEmpty {
                Text("No tags yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                let columns = [GridItem(.adaptive(minimum: 60), spacing: BrandSpacing.xs)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: BrandSpacing.xs) {
                    ForEach(vm.tags, id: \.self) { tag in
                        Button { vm.removeTag(tag) } label: {
                            HStack(spacing: 4) {
                                Text(tag).font(.brandLabelLarge()).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, BrandSpacing.xxs)
                            .foregroundStyle(.bizarreOnSurface)
                            .background(Color.bizarreSurface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
            }
            if let err = vm.errorMessage {
                Text(err).font(.brandLabelSmall()).foregroundStyle(.bizarreError)
            }
        }
    }

    private var entrySection: some View {
        HStack(spacing: BrandSpacing.sm) {
            TextField("Add tag…", text: $vm.query)
                .font(.brandBodyMedium())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Tag entry field")
                .onSubmit { vm.addTag() }
            if !vm.query.isEmpty {
                Button { vm.addTag() } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .font(.system(size: 22))
                }
                .accessibilityLabel("Add tag \(vm.query)")
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    @ViewBuilder
    private var limitWarning: some View {
        if vm.tags.count >= 20 {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.bizarreWarning)
                Text("Maximum 20 tags reached.").font(.brandLabelSmall())
            }
        } else if vm.tags.count >= 10 {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "info.circle.fill").foregroundStyle(.bizarreTeal)
                Text("\(vm.tags.count) of 20 tags used.").font(.brandLabelSmall())
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class LeadTagEditorViewModel {
    public var tags: [String]
    public var query: String = ""
    public private(set) var isSaving: Bool = false
    public private(set) var savedSuccessfully: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let leadId: Int64

    public init(api: APIClient, leadId: Int64, initialTags: [String]) {
        self.api = api
        self.leadId = leadId
        self.tags = initialTags
    }

    public func addTag() {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !tags.contains(t), tags.count < 20 else { return }
        tags.append(t)
        query = ""
    }

    public func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    public func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await api.setLeadTags(leadId: leadId, tags: tags)
            savedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
