import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class ExpenseDetailViewModel {
    public enum State: Sendable {
        case loading
        case loaded(Expense)
        case failed(String)
    }

    public var state: State = .loading
    public private(set) var isDeleting: Bool = false
    public private(set) var deleteError: String?
    public private(set) var didDelete: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let id: Int64

    public init(api: APIClient, id: Int64) {
        self.api = api
        self.id = id
    }

    public func load() async {
        if case .loaded = state { /* soft refresh — keep stale data visible */ } else {
            state = .loading
        }
        do {
            let expense = try await api.getExpense(id: id)
            state = .loaded(expense)
        } catch {
            AppLog.ui.error("Expense detail load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public func delete() async {
        guard !isDeleting else { return }
        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteExpense(id: id)
            didDelete = true
        } catch {
            AppLog.ui.error("Expense delete failed: \(error.localizedDescription, privacy: .public)")
            deleteError = error.localizedDescription
        }
    }

    /// Called after receipt is successfully attached — soft-reload to pick up new path.
    public func refreshAfterReceiptAttach() async {
        await load()
    }
}

// MARK: - View

public struct ExpenseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExpenseDetailViewModel
    @State private var showEdit: Bool = false
    @State private var showReceiptAttach: Bool = false
    @State private var showDeleteConfirm: Bool = false
    private let api: APIClient

    public init(api: APIClient, id: Int64) {
        self.api = api
        _vm = State(wrappedValue: ExpenseDetailViewModel(api: api, id: id))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(navigationTitle)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar { detailToolbar }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await vm.load() } }) {
            if case .loaded(let exp) = vm.state {
                ExpenseEditView(api: api, expenseId: exp.id)
            }
        }
        .sheet(isPresented: $showReceiptAttach) {
            if case .loaded(let exp) = vm.state {
                ReceiptAttachView(api: api, expenseId: exp.id, authToken: nil) { _ in
                    Task { await vm.refreshAfterReceiptAttach() }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog(
            "Delete this expense?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await vm.delete()
                    if vm.didDelete { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Delete failed", isPresented: Binding(
            get: { vm.deleteError != nil },
            set: { _ in }
        )) {
            Button("OK") { }
        } message: {
            Text(vm.deleteError ?? "")
        }
    }

    private var navigationTitle: String {
        if case .loaded(let e) = vm.state {
            return e.category?.capitalized ?? "Expense"
        }
        return "Expense"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if case .loaded = vm.state {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit expense")
                .accessibilityIdentifier("expenses.detail.edit")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: vm.isDeleting ? "clock" : "trash")
                }
                .disabled(vm.isDeleting)
                .accessibilityLabel("Delete expense")
                .accessibilityIdentifier("expenses.detail.delete")
            }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading expense")
        case .failed(let msg):
            errorView(msg)
        case .loaded(let expense):
            loadedBody(expense)
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load expense")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Try loading expense again")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loaded body

    @ViewBuilder
    private func loadedBody(_ expense: Expense) -> some View {
        if Platform.isCompact {
            compactBody(expense)
        } else {
            regularBody(expense)
        }
    }

    private func compactBody(_ expense: Expense) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                headerCard(expense)
                if let desc = expense.description, !desc.isEmpty {
                    descriptionCard(desc)
                }
                if hasVendorPayment(expense) {
                    vendorPaymentCard(expense)
                }
                metaCard(expense)
                receiptCard(expense)
            }
            .padding(BrandSpacing.base)
        }
    }

    private func regularBody(_ expense: Expense) -> some View {
        ScrollView {
            // Two-column grid on iPad
            Grid(alignment: .topLeading, horizontalSpacing: BrandSpacing.lg, verticalSpacing: BrandSpacing.lg) {
                GridRow {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        headerCard(expense)
                        if let desc = expense.description, !desc.isEmpty {
                            descriptionCard(desc)
                        }
                        if hasVendorPayment(expense) {
                            vendorPaymentCard(expense)
                        }
                    }
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        metaCard(expense)
                        receiptCard(expense)
                    }
                }
            }
            .padding(BrandSpacing.lg)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header card

    private func headerCard(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                categoryChip(expense.category)
                Spacer(minLength: BrandSpacing.sm)
                Text(formatMoney(expense.amount ?? 0))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel("Amount \(formatMoney(expense.amount ?? 0))")
            }
            if let date = expense.date, !date.isEmpty {
                Text(date)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Date \(date)")
            }
            if let status = expense.status, !status.isEmpty {
                statusBadge(status)
            }
            if expense.isReimbursable == true {
                Label("Reimbursable", systemImage: "arrow.uturn.left.circle")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Marked reimbursable")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerA11y(expense))
    }

    private func categoryChip(_ category: String?) -> some View {
        Text(category?.capitalized ?? "Uncategorized")
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnOrange)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Color.bizarreOrange, in: Capsule())
            .accessibilityLabel("Category \(category?.capitalized ?? "Uncategorized")")
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch ExpenseStatus(rawValue: status) {
            case .approved: return Color.bizarreSuccess
            case .denied: return Color.bizarreError
            default: return Color.bizarreOnSurfaceMuted
            }
        }()
        return Text(status.capitalized)
            .font(.brandLabelLarge())
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Approval status: \(status)")
    }

    private func headerA11y(_ expense: Expense) -> String {
        var parts: [String] = [expense.category?.capitalized ?? "Uncategorized"]
        parts.append(formatMoney(expense.amount ?? 0))
        if let date = expense.date, !date.isEmpty { parts.append(date) }
        if let status = expense.status, !status.isEmpty { parts.append(status) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Description card

    private func descriptionCard(_ desc: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Description")
            Text(desc)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(desc)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Vendor / payment card

    private func hasVendorPayment(_ expense: Expense) -> Bool {
        let hasVendor = !(expense.vendor?.isEmpty ?? true)
        let hasPayment = !(expense.paymentMethod?.isEmpty ?? true)
        let hasTax = expense.taxAmount != nil
        let hasNotes = !(expense.notes?.isEmpty ?? true)
        return hasVendor || hasPayment || hasTax || hasNotes
    }

    private func vendorPaymentCard(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Vendor & Payment")
            if let vendor = expense.vendor, !vendor.isEmpty {
                metaRow(label: "Vendor", value: vendor)
            }
            if let method = expense.paymentMethod, !method.isEmpty {
                metaRow(label: "Payment", value: method)
            }
            if let tax = expense.taxAmount {
                metaRow(label: "Tax", value: formatMoney(tax))
            }
            if let notes = expense.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Notes")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(notes)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, BrandSpacing.xs)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Meta card

    private func metaCard(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Details")
            if let createdBy = expense.createdByName {
                metaRow(label: "Added by", value: createdBy)
            }
            if let created = expense.createdAt, !created.isEmpty {
                metaRow(label: "Created", value: created)
            }
            if let updated = expense.updatedAt, !updated.isEmpty, updated != expense.createdAt {
                metaRow(label: "Updated", value: updated)
            }
            metaRow(label: "Expense ID", value: "#\(expense.id)")
            if let subtype = expense.expenseSubtype, !subtype.isEmpty, subtype != "general" {
                metaRow(label: "Type", value: subtype.capitalized)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer(minLength: BrandSpacing.sm)
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Receipt card

    @ViewBuilder
    private func receiptCard(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                sectionHeader("Receipt")
                Spacer()
                Button {
                    showReceiptAttach = true
                } label: {
                    Label(expense.resolvedReceiptPath != nil ? "Replace" : "Attach", systemImage: "plus.circle")
                        .font(.brandLabelLarge())
                }
                .buttonStyle(.borderless)
                .tint(.bizarreOrange)
                .accessibilityLabel(expense.resolvedReceiptPath != nil ? "Replace receipt photo" : "Attach receipt photo")
                .accessibilityIdentifier("expenses.detail.attachReceipt")
            }
            if let path = expense.resolvedReceiptPath, !path.isEmpty {
                receiptImageView(path: path)
                if let uploadedAt = expense.receiptUploadedAt, !uploadedAt.isEmpty {
                    Text("Uploaded \(uploadedAt)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else {
                emptyReceiptView
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func receiptImageView(path: String) -> some View {
        ReceiptImageView(api: api, path: path)
    }

    private var emptyReceiptView: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 24))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No receipt attached")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityLabel("No receipt attached")
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .tracking(0.8)
            .accessibilityAddTraits(.isHeader)
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Receipt image loader

/// Resolves a server-relative receipt path to a full URL using the client's
/// current base URL and renders it via `AsyncImage`.
private struct ReceiptImageView: View {
    let api: APIClient
    let path: String

    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .accessibilityLabel("Loading receipt image")
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Receipt photo")
                    case .failure:
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "photo.slash")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                            Text("Receipt couldn't load")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .accessibilityLabel("Receipt image failed to load")
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityLabel("Resolving receipt URL")
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        guard let base = await api.currentBaseURL() else { return }
        if path.hasPrefix("http") {
            resolvedURL = URL(string: path)
        } else {
            let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
            resolvedURL = base.appendingPathComponent(trimmed)
        }
    }
}
