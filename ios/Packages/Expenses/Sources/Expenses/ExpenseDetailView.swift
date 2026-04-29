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
    // §11.2 Approval workflow
    public private(set) var isApproving: Bool = false
    public private(set) var isDenying: Bool = false
    public private(set) var approvalError: String?

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

    // MARK: - §11.2 Approval workflow

    /// Approve expense via `POST /expenses/:id/approve`.
    public func approve() async {
        guard !isApproving else { return }
        approvalError = nil
        isApproving = true
        defer { isApproving = false }
        do {
            try await api.approveExpense(id: id)
            await load()
        } catch {
            AppLog.ui.error("Expense approve failed: \(error.localizedDescription, privacy: .public)")
            approvalError = error.localizedDescription
        }
    }

    /// Deny expense via `POST /expenses/:id/deny` with a reason comment.
    public func deny(reason: String) async {
        guard !isDenying else { return }
        approvalError = nil
        isDenying = true
        defer { isDenying = false }
        do {
            try await api.denyExpense(id: id, reason: reason)
            await load()
        } catch {
            AppLog.ui.error("Expense deny failed: \(error.localizedDescription, privacy: .public)")
            approvalError = error.localizedDescription
        }
    }
}

// MARK: - View

public struct ExpenseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExpenseDetailViewModel
    @State private var showEdit: Bool = false
    @State private var showReceiptAttach: Bool = false
    @State private var showDeleteConfirm: Bool = false
    /// §11.2 Approval — deny reason sheet
    @State private var showDenySheet: Bool = false
    @State private var denyReasonText: String = ""
    /// §11.2 — full-screen receipt zoom sheet
    @State private var showReceiptZoom: Bool = false
    @State private var zoomReceiptPath: String?
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
        // §11.2 — full-screen receipt zoom with pinch
        .fullScreenCover(isPresented: $showReceiptZoom) {
            if let path = zoomReceiptPath {
                ReceiptZoomView(api: api, path: path) {
                    showReceiptZoom = false
                }
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
        // §11.2 Approval error alert
        .alert("Action failed", isPresented: Binding(
            get: { vm.approvalError != nil },
            set: { _ in }
        )) {
            Button("OK") { }
        } message: {
            Text(vm.approvalError ?? "")
        }
        // §11.2 Deny reason sheet
        .sheet(isPresented: $showDenySheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    Text("Provide a reason for denying this expense.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.horizontal)
                    TextEditor(text: $denyReasonText)
                        .frame(minHeight: 100)
                        .padding(BrandSpacing.sm)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .accessibilityLabel("Denial reason")
                    Spacer()
                }
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
                .navigationTitle("Deny Expense")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDenySheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") {
                            let reason = denyReasonText
                            showDenySheet = false
                            denyReasonText = ""
                            Task { await vm.deny(reason: reason) }
                        }
                        .disabled(denyReasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Submit denial reason")
                    }
                }
            }
            .presentationDetents([.medium])
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
                .keyboardShortcut("E", modifiers: .command)
                .accessibilityLabel("Edit expense")
                .accessibilityIdentifier("expenses.detail.edit")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: vm.isDeleting ? "clock" : "trash")
                }
                .disabled(vm.isDeleting)
                .keyboardShortcut(.delete, modifiers: .command)
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
                // §11.2 Approval workflow — show approve/deny buttons when pending
                if expense.status == ExpenseStatus.pending.rawValue {
                    approvalActionsCard(expense)
                }
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
                        // §11.2 Approval workflow (iPad)
                        if expense.status == ExpenseStatus.pending.rawValue {
                            approvalActionsCard(expense)
                        }
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

    // MARK: - §11.2 Approval actions card

    private func approvalActionsCard(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Manager Action")
            Text("This expense is pending approval.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.md) {
                Button {
                    Task { await vm.approve() }
                } label: {
                    HStack {
                        if vm.isApproving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                        }
                        Text("Approve")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreSuccess)
                .disabled(vm.isApproving || vm.isDenying)
                .accessibilityLabel("Approve expense")
                .accessibilityIdentifier("expenses.detail.approve")

                Button {
                    denyReasonText = ""
                    showDenySheet = true
                } label: {
                    HStack {
                        if vm.isDenying {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "xmark.circle.fill").accessibilityHidden(true)
                        }
                        Text("Deny")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreError)
                .disabled(vm.isApproving || vm.isDenying)
                .accessibilityLabel("Deny expense")
                .accessibilityIdentifier("expenses.detail.deny")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreWarning.opacity(0.4), lineWidth: 0.5))
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

    // MARK: - §11 Category color chips — each category maps to a distinct hue

    /// Returns a per-category background color so chips carry visual meaning at
    /// a glance (Travel = blue, Payroll = teal, Taxes = red, etc.).
    /// Falls back to the brand orange for unknown / nil categories.
    private static func categoryChipColor(for category: String?) -> Color {
        switch category?.lowercased() {
        case "travel":      return Color(red: 0.18, green: 0.53, blue: 0.92)   // blue
        case "payroll":     return Color(red: 0.13, green: 0.68, blue: 0.49)   // teal-green
        case "taxes":       return Color(red: 0.85, green: 0.27, blue: 0.27)   // red
        case "insurance":   return Color(red: 0.56, green: 0.27, blue: 0.87)   // violet
        case "software":    return Color(red: 0.12, green: 0.60, blue: 0.72)   // cyan
        case "marketing":   return Color(red: 0.95, green: 0.60, blue: 0.07)   // amber
        case "rent":        return Color(red: 0.42, green: 0.42, blue: 0.70)   // slate-blue
        case "utilities":   return Color(red: 0.22, green: 0.65, blue: 0.40)   // green
        case "shipping":    return Color(red: 0.65, green: 0.45, blue: 0.18)   // brown
        case "maintenance": return Color(red: 0.50, green: 0.55, blue: 0.60)   // steel
        default:            return .bizarreOrange
        }
    }

    private func categoryChip(_ category: String?) -> some View {
        let bg = Self.categoryChipColor(for: category)
        return Text(category?.capitalized ?? "Uncategorized")
            .font(.brandLabelLarge())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(bg, in: Capsule())
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

    /// §11 Vendor copy chip — pressing the chip copies the vendor name to the
    /// pasteboard and briefly shows a "Copied!" confirmation label.
    private func vendorCopyChip(_ vendor: String) -> some View {
        VendorCopyChip(vendor: vendor)
    }

    private func vendorPaymentCard(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Vendor & Payment")
            if let vendor = expense.vendor, !vendor.isEmpty {
                // §11 Vendor copy chip — tap to copy vendor name to clipboard
                vendorCopyChip(vendor)
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

    /// §11.2 — tap receipt thumbnail → full-screen zoom sheet.
    private func receiptImageView(path: String) -> some View {
        Button {
            zoomReceiptPath = path
            showReceiptZoom = true
        } label: {
            ReceiptImageView(api: api, path: path)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View receipt full screen")
        .accessibilityHint("Double-tap to open full-screen view with pinch-to-zoom")
    }

    /// §11 Receipt photo placeholder — dashed-border drop zone that communicates
    /// the expected content even before a photo is attached.
    private var emptyReceiptView: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.6))
                .accessibilityHidden(true)
            Text("No receipt attached")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Tap "Attach" to add a photo or scan")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundStyle(Color.bizarreOutline.opacity(0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No receipt attached. Tap Attach to add a photo or scan.")
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .tracking(0.8)
            .accessibilityAddTraits(.isHeader)
    }

    /// §11 Amount format — uses the device locale's currency so non-USD tenants
    /// see their local symbol (€, £, ¥ …) rather than a hard-coded "$".
    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current          // honours device region setting
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
}

// MARK: - §11 Vendor copy chip

/// Tappable chip that copies the vendor name to the pasteboard.
/// Shows a brief "Copied!" confirmation label using `@State` — no UIKit needed.
private struct VendorCopyChip: View {
    let vendor: String
    @State private var copied = false

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIPasteboard.general.string = vendor
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(vendor, forType: .string)
            #endif
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(.easeInOut(duration: 0.2)) { copied = false }
            }
        } label: {
            HStack(spacing: BrandSpacing.xxs) {
                Text(copied ? "Copied!" : vendor)
                    .font(.brandBodyMedium())
                    .foregroundStyle(copied ? Color.bizarreSuccess : Color.bizarreOnSurface)
                    .animation(.easeInOut(duration: 0.15), value: copied)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(copied ? Color.bizarreSuccess : Color.bizarreOnSurfaceMuted)
                    .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Color.bizarreSurface1, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vendor: \(vendor). Double-tap to copy.")
        .accessibilityHint("Copies vendor name to clipboard")
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
