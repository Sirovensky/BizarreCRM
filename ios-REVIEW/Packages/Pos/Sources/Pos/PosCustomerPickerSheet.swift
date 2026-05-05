#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Customers

/// §16.4 — "Find existing customer" sheet. Search bar drives
/// `CustomerRepository.list(keyword:)`; tapping a row attaches as
/// `PosCustomer`. Detents `[.medium, .large]`.
struct PosCustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let repo: CustomerRepository
    let onPick: (PosCustomer) -> Void
    let onCreateNew: (() -> Void)?

    @State private var query: String = ""
    @State private var results: [CustomerSummary] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(
        repo: CustomerRepository,
        onPick: @escaping (PosCustomer) -> Void,
        onCreateNew: (() -> Void)? = nil
    ) {
        self.repo = repo
        self.onPick = onPick
        self.onCreateNew = onCreateNew
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                        .padding(.bottom, BrandSpacing.xs)
                    content
                }
            }
            .navigationTitle("Find customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let onCreateNew {
                    ToolbarItem(placement: .primaryAction) {
                        Button { dismiss(); onCreateNew() } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        .accessibilityLabel("Create new customer")
                        .accessibilityIdentifier("pos.customerPicker.create")
                    }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            TextField("Name, email, or phone", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: query) { _, _ in onQueryChange() }
                .accessibilityIdentifier("pos.customerPicker.search")
            if !query.isEmpty {
                Button { query = ""; onQueryChange() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .frame(minHeight: 48)
        .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && results.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage {
            errorState(err)
        } else if results.isEmpty {
            emptyState
        } else {
            List(results) { summary in
                Button {
                    BrandHaptics.success()
                    onPick(PosCustomerMapper.from(summary))
                    dismiss()
                } label: {
                    PosCustomerPickerRow(customer: summary)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("pos.customerPicker.row.\(summary.id)")
                .accessibilityLabel("Attach \(summary.displayName) to cart")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func errorState(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load customers")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(err)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: query.isEmpty ? "person.2" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(query.isEmpty ? "Search by name, email, or phone." : "No matches for \u{201C}\(query)\u{201D}")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            if let onCreateNew {
                Button {
                    dismiss()
                    onCreateNew()
                } label: {
                    Label("Create new customer", systemImage: "person.crop.circle.badge.plus")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOrange)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.plain)
                .background(Color.bizarreSurface1, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 0.5))
                .accessibilityIdentifier("pos.customerPicker.emptyCreate")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func onQueryChange() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await load()
        }
    }

    private func load() async {
        isLoading = results.isEmpty
        defer { isLoading = false }
        errorMessage = nil
        do {
            let kw = query.trimmingCharacters(in: .whitespacesAndNewlines)
            results = try await repo.list(keyword: kw.isEmpty ? nil : kw)
        } catch {
            AppLog.ui.error("Customer picker load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

enum PosCustomerMapper {
    static func from(_ summary: CustomerSummary) -> PosCustomer {
        PosCustomer(
            id: summary.id,
            displayName: summary.displayName,
            email: summary.email,
            phone: summary.phone ?? summary.mobile
        )
    }
}

struct PosCustomerPickerRow: View {
    let customer: CustomerSummary

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
                Text(customer.initials)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(customer.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let line = customer.contactLine {
                    Text(line)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
#endif
