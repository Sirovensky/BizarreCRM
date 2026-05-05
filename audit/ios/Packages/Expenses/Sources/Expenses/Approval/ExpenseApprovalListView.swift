import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ExpenseApprovalListView

/// Manager view: list of pending expense claims with approve / deny actions.
/// Liquid Glass toolbar. Audit log accessible via toolbar.
public struct ExpenseApprovalListView: View {
    @State private var vm: ExpenseApprovalViewModel
    @State private var showingAuditLog: Bool = false
    @State private var denyingExpense: Expense?
    @State private var denyReasonText: String = ""

    public init(api: APIClient, monthlyBudgetCents: Int? = nil) {
        _vm = State(wrappedValue: ExpenseApprovalViewModel(api: api, monthlyBudgetCents: monthlyBudgetCents))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            contentView
        }
        .navigationTitle("Pending Approvals")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .task { await vm.loadPending() }
        .refreshable { await vm.loadPending() }
        .sheet(item: $denyingExpense) { expense in
            denySheet(expense: expense)
        }
        .sheet(isPresented: $showingAuditLog) {
            auditLogSheet
        }
        .alert("Budget Warning", isPresented: Binding(
            get: { vm.budgetWarning != nil },
            set: { if !$0 { vm.budgetWarning = nil } }
        )) {
            Button("Dismiss", role: .cancel) { vm.budgetWarning = nil }
        } message: {
            if let warning = vm.budgetWarning {
                Text("This approval puts the employee \(String(format: "%.0f%%", warning.overagePercent)) over their monthly budget limit.")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch vm.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading pending approvals")

        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Text("Failed to load").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.loadPending() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .padding(BrandSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let expenses):
            if expenses.isEmpty {
                emptyState
            } else {
                approvalList(expenses)
            }
        }
    }

    private func approvalList(_ expenses: [Expense]) -> some View {
        List {
            if let errMsg = vm.errorMessage {
                Section {
                    Text(errMsg).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                }
            }
            Section {
                ForEach(expenses) { expense in
                    PendingExpenseRow(
                        expense: expense,
                        isProcessing: vm.processingId == expense.id,
                        onApprove: { Task { await vm.approve(expense: expense) } },
                        onDeny: { denyingExpense = expense }
                    )
                }
            } header: {
                Text("\(expenses.count) pending")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("All caught up")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("No expenses are pending approval.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No pending approvals. All caught up.")
    }

    // MARK: - Deny sheet

    private func denySheet(expense: Expense) -> some View {
        NavigationStack {
            Form {
                Section("Denial reason") {
                    TextField("Required", text: $denyReasonText, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Denial reason (required)")
                        .accessibilityIdentifier("approval.denyReason")
                }
                Section {
                    HStack {
                        Text("Expense")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(expense.category?.capitalized ?? "—")
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    HStack {
                        Text("Amount")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(formatMoney(expense.amount ?? 0))
                            .foregroundStyle(.bizarreError)
                            .monospacedDigit()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Deny Expense")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { denyingExpense = nil; denyReasonText = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Deny") {
                        let reason = denyReasonText
                        let exp = expense
                        denyingExpense = nil
                        denyReasonText = ""
                        Task { await vm.deny(expense: exp, reason: reason) }
                    }
                    .disabled(denyReasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .brandGlass()
                    .tint(.bizarreError)
                    .accessibilityLabel("Confirm denial with reason")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Audit log sheet

    private var auditLogSheet: some View {
        NavigationStack {
            List {
                if vm.auditLog.isEmpty {
                    Text("No decisions recorded this session.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } else {
                    ForEach(vm.auditLog) { entry in
                        AuditLogRow(entry: entry)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Audit Log")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingAuditLog = false }
                        .brandGlass()
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingAuditLog = true
            } label: {
                Label("Audit Log", systemImage: "list.clipboard")
            }
            .brandGlass()
            .accessibilityLabel("View audit log of approval decisions")
        }
    }

    // MARK: - Helpers

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - PendingExpenseRow

private struct PendingExpenseRow: View {
    let expense: Expense
    let isProcessing: Bool
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category?.capitalized ?? "Uncategorized")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let name = expense.createdByName {
                    Text(name)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let date = expense.date {
                    Text(date)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: BrandSpacing.sm)

            if isProcessing {
                ProgressView()
                    .accessibilityLabel("Processing")
            } else {
                VStack(spacing: BrandSpacing.xs) {
                    Text(formatMoney(expense.amount ?? 0))
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()

                    HStack(spacing: BrandSpacing.xs) {
                        Button {
                            onApprove()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 24))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Approve \(expense.category?.capitalized ?? "expense") from \(expense.createdByName ?? "employee")")

                        Button {
                            onDeny()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.bizarreError)
                                .font(.system(size: 24))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Deny \(expense.category?.capitalized ?? "expense") from \(expense.createdByName ?? "employee")")
                    }
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowA11y)
    }

    private var rowA11y: String {
        var parts: [String] = []
        parts.append(expense.category?.capitalized ?? "Uncategorized")
        if let name = expense.createdByName { parts.append(name) }
        parts.append(formatMoney(expense.amount ?? 0))
        if let date = expense.date { parts.append(date) }
        return parts.joined(separator: ". ")
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - AuditLogRow

private struct AuditLogRow: View {
    let entry: ApprovalAuditEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Expense #\(entry.expenseId)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                switch entry.decision {
                case .approved:
                    Text("Approved")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.green)
                case .denied(let reason):
                    Text("Denied: \(reason)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreError)
                        .lineLimit(2)
                }
                Text(entry.decidedAt.formatted(.dateTime))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            decisionIcon
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var decisionIcon: some View {
        Group {
            switch entry.decision {
            case .approved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .denied:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.bizarreError)
            }
        }
        .font(.system(size: 20))
        .accessibilityHidden(true)
    }

    private var a11yLabel: String {
        switch entry.decision {
        case .approved:
            return "Expense \(entry.expenseId) approved on \(entry.decidedAt.formatted(.dateTime))"
        case .denied(let reason):
            return "Expense \(entry.expenseId) denied. Reason: \(reason). On \(entry.decidedAt.formatted(.dateTime))"
        }
    }
}
