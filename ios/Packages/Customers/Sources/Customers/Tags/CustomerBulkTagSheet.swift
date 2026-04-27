#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// MARK: - §5.7 Bulk-assign tags via list multi-select

/// Sheet for assigning one or more tags to all selected customers at once.
/// Opened from the BulkActionBar when customers are selected in the list.
public struct CustomerBulkTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var selectedTags: Set<String> = []
    @State private var suggestions: [String] = []
    @State private var isSuggestLoading = false
    @State private var isSaving = false
    @State private var saveError: String?
    private let api: APIClient
    private let selectedCustomerIds: [Int64]
    private let onDone: ([String]) -> Void
    private var suggestTask: Task<Void, Never>?

    public init(api: APIClient, selectedCustomerIds: [Int64], onDone: @escaping ([String]) -> Void) {
        self.api = api
        self.selectedCustomerIds = selectedCustomerIds
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    headerInfo
                    if !selectedTags.isEmpty {
                        selectedSection
                    }
                    searchSection
                    if !suggestions.isEmpty {
                        suggestionsSection
                    }
                    if let err = saveError {
                        Text(err)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                            .padding(.horizontal, BrandSpacing.base)
                    }
                }
                .padding(.vertical, BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Bulk Assign Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Apply") {
                        Task { await applyTags() }
                    }
                    .disabled(selectedTags.isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerInfo: some View {
        Text("Assign tags to \(selectedCustomerIds.count) selected customer\(selectedCustomerIds.count == 1 ? "" : "s").")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Selected chips

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("TAGS TO ASSIGN")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
                .padding(.horizontal, BrandSpacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                        tagChip(tag)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            Text(tag)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
            Button {
                selectedTags.remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.system(size: 14))
            }
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreOrange.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("ADD TAGS")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
                .padding(.horizontal, BrandSpacing.base)

            HStack(spacing: BrandSpacing.sm) {
                TextField("Search or type a tag…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: query) { _, new in scheduleAutosuggest(new) }
                    .accessibilityLabel("Tag search field")

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if !t.isEmpty { selectedTags.insert(t) }
                        query = ""
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.bizarreOrange)
                            .font(.system(size: 22))
                    }
                    .accessibilityLabel("Add tag")
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("SUGGESTIONS")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
                .padding(.horizontal, BrandSpacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button {
                            selectedTags.insert(tag)
                        } label: {
                            Text(tag)
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurface)
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(Color.bizarreSurface2, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Suggest tag: \(tag)")
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    // MARK: - Autosuggest

    private func scheduleAutosuggest(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { suggestions = []; return }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            isSuggestLoading = true
            defer { isSuggestLoading = false }
            if let raw = try? await api.suggestCustomerTags(query: trimmed) {
                suggestions = raw.filter { !selectedTags.contains($0) }
            }
        }
    }

    // MARK: - Save

    private func applyTags() async {
        guard !selectedTags.isEmpty else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let tags = Array(selectedTags)
        do {
            for tag in tags {
                let req = BulkTagRequest(customerIds: selectedCustomerIds, tag: tag)
                try await api.bulkTagCustomers(req)
            }
            onDone(tags)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// Note: `bulkTagCustomers(_:)` is defined in APIClient+Customers.swift.
#endif
