#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Customers

/// "Find existing customer" sheet (§16.4). Thin search UI on top of the
/// shared `CustomerRepository.list(keyword:)` call already in the Customers
/// package — a hit taps through to `attach(customer:)` and dismisses. On an
/// empty store the sheet CTAs into the "Create new" flow rather than a
/// dead-end.
///
/// Presentation detents `[.medium, .large]` so the cashier can peek at the
/// top-of-list results without losing sight of the cart beneath.
struct PosCustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repo: CustomerRepository
    let api: APIClient
    let onPick: (PosCustomer) -> Void

    @State private var query: String = ""
    @State private var results: [CustomerSummary] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var showingCreate: Bool = false

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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create new customer")
                    .accessibilityIdentifier("pos.findCustomer.create")
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingCreate) {
                CustomerCreateSheetWrapper(api: api) { created in
                    onPick(created)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            TextField("Name, email, or phone", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: query) { _, new in onQueryChange(new) }
                .accessibilityIdentifier("pos.customerPicker.search")
            if !query.isEmpty {
                Button {
                    query = ""
                    onQueryChange("")
                } label: {
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

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
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
        } else if results.isEmpty {
            emptyState
        } else {
            List(results) { customer in
                Button {
                    BrandHaptics.success()
                    onPick(map(customer))
                    dismiss()
                } label: {
                    PosCustomerPickerRow(customer: customer)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("pos.customerPicker.row.\(customer.id)")
                .accessibilityLabel("Attach \(customer.displayName) to cart")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(query.isEmpty ? "No customers yet" : "No matches")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(query.isEmpty
                 ? "Create a new customer to attach to this cart."
                 : "Try a different name, phone, or email.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button {
                showingCreate = true
            } label: {
                Label("Create new customer", systemImage: "person.crop.circle.badge.plus")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOrange)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .background(Color.bizarreSurface1, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 0.5))
            .accessibilityIdentifier("pos.customerPicker.createFromEmpty")
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.top, BrandSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Data

    private func onQueryChange(_ new: String) {
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
            errorMessage = error.localizedDescription
        }
    }

    private func map(_ c: CustomerSummary) -> PosCustomer {
        PosCustomer(
            id: c.id,
            displayName: c.displayName,
            email: c.email,
            phone: c.phone ?? c.mobile
        )
    }
}

/// Single result row — avatar initials + name + primary contact line.
private struct PosCustomerPickerRow: View {
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
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }
}

/// Wraps `CustomerCreateView` so the Pos package can observe the
/// `createdId` handoff without exposing the Customers view model's API.
/// When `createdId` flips non-nil, we synthesise a `PosCustomer` and pass
/// it up so the cart auto-attaches without an extra network round-trip.
struct CustomerCreateSheetWrapper: View {
    @Environment(\.dismiss) private var dismiss
    let api: APIClient
    let onCreated: (PosCustomer) -> Void

    @State private var vm: CustomerCreateViewModel

    init(api: APIClient, onCreated: @escaping (PosCustomer) -> Void) {
        self.api = api
        self.onCreated = onCreated
        _vm = State(wrappedValue: CustomerCreateViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            CustomerFormView(
                firstName: $vm.firstName,
                lastName: $vm.lastName,
                email: $vm.email,
                phone: $vm.phone,
                mobile: $vm.mobile,
                organization: $vm.organization,
                address1: $vm.address1,
                city: $vm.city,
                state: $vm.state,
                postcode: $vm.postcode,
                notes: $vm.notes,
                errorMessage: vm.errorMessage
            )
            .navigationTitle("New customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
        }
    }

    private func save() async {
        await vm.submit()
        guard let id = vm.createdId else { return }
        let trimmedFirst = vm.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast  = vm.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [trimmedFirst, trimmedLast]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let customer = PosCustomer(
            id: id == PendingSyncCustomerId ? nil : id,
            displayName: name.isEmpty ? "New customer" : name,
            email: vm.email.isEmpty ? nil : vm.email,
            phone: vm.phone.isEmpty ? (vm.mobile.isEmpty ? nil : vm.mobile) : vm.phone
        )
        onCreated(customer)
        dismiss()
    }
}
#endif
