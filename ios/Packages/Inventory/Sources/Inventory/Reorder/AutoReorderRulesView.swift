#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Auto-Reorder Rules Admin View
//
// Shows all items with reorder rules configured.
// Allows editing threshold + reorder qty + supplier.
// "Run now" button generates draft POs via AutoPOGenerator.

// MARK: Models

public struct ReorderRule: Identifiable, Sendable, Decodable {
    public let id: Int64          // item id
    public let sku: String
    public let name: String
    public let threshold: Int
    public let reorderQty: Int
    public let supplierName: String?
    public let inStock: Int

    public var isTriggered: Bool { inStock <= threshold }

    enum CodingKeys: String, CodingKey {
        case id, sku, name, threshold
        case reorderQty = "reorder_qty"
        case supplierName = "supplier_name"
        case inStock = "in_stock"
    }
}

// MARK: ViewModel

@MainActor
@Observable
public final class AutoReorderRulesViewModel {
    public private(set) var rules: [ReorderRule] = []
    public private(set) var isLoading = false
    public private(set) var isRunningNow = false
    public private(set) var errorMessage: String?
    public private(set) var successMessage: String?
    public var editingRule: ReorderRule?
    public var editThreshold: String = ""
    public var editReorderQty: String = ""
    public var showEditSheet = false

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { rules = try await api.listReorderRules() }
        catch { errorMessage = error.localizedDescription }
    }

    public func beginEdit(rule: ReorderRule) {
        editingRule = rule
        editThreshold = String(rule.threshold)
        editReorderQty = String(rule.reorderQty)
        showEditSheet = true
    }

    public func saveEdit() async {
        guard let rule = editingRule,
              let threshold = Int(editThreshold),
              let qty = Int(editReorderQty) else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await api.updateInventoryReorderRule(id: rule.id, threshold: threshold, reorderQty: qty)
            if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                // Rebuild with new values
                let updated = ReorderRule(
                    id: rule.id, sku: rule.sku, name: rule.name,
                    threshold: threshold, reorderQty: qty,
                    supplierName: rule.supplierName, inStock: rule.inStock
                )
                rules[idx] = updated
            }
            showEditSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runNow() async {
        isRunningNow = true; errorMessage = nil; successMessage = nil
        defer { isRunningNow = false }
        do {
            let triggeredIds = rules.filter(\.isTriggered).map(\.id)
            guard !triggeredIds.isEmpty else {
                successMessage = "No items below threshold — nothing to order."
                return
            }
            let draftCount = try await api.runAutoReorder(itemIds: triggeredIds)
            successMessage = "\(draftCount) draft PO\(draftCount == 1 ? "" : "s") created."
            BrandHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: View

public struct AutoReorderRulesView: View {
    @State private var vm: AutoReorderRulesViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: AutoReorderRulesViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Auto-Reorder Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showEditSheet) { editSheet }
        .overlay(alignment: .bottom) { feedbackBanner }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.rules.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.rules.isEmpty {
            emptyState
        } else {
            ruleList
        }
    }

    private var ruleList: some View {
        List {
            Section {
                triggeredBanner
            }
            ForEach(vm.rules) { rule in
                ruleRow(rule)
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var triggeredBanner: some View {
        let triggered = vm.rules.filter(\.isTriggered)
        if !triggered.isEmpty {
            Label(
                "\(triggered.count) item\(triggered.count == 1 ? "" : "s") below threshold — ready to order.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(Color.bizarreWarning)
            .font(.bizarreCaption)
            .padding(.vertical, 4)
        }
    }

    private func ruleRow(_ rule: ReorderRule) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(rule.isTriggered ? Color.bizarreError : Color.bizarrePrimary)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.bizarreBody)
                    .fontWeight(.medium)
                Text("Threshold: \(rule.threshold) · Reorder qty: \(rule.reorderQty)")
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
                if let supplier = rule.supplierName {
                    Text("Supplier: \(supplier)")
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreTextSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("In stock: \(rule.inStock)")
                    .font(.bizarreCaption)
                    .foregroundStyle(rule.isTriggered ? Color.bizarreError : Color.bizarreTextSecondary)
                if rule.isTriggered {
                    Label("Triggered", systemImage: "bell.badge")
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreError)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                vm.beginEdit(rule: rule)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.bizarrePrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(rule.name), threshold \(rule.threshold), \(rule.inStock) in stock\(rule.isTriggered ? ", triggered" : "")"
        )
    }

    // MARK: Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Rule for \(vm.editingRule?.name ?? "")") {
                    LabeledContent("Reorder threshold") {
                        TextField("e.g. 5", text: $vm.editThreshold)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Reorder quantity") {
                        TextField("e.g. 20", text: $vm.editReorderQty)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let supplier = vm.editingRule?.supplierName {
                    Section("Supplier") {
                        Text(supplier)
                            .font(.bizarreBody)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                }
            }
            .navigationTitle("Edit Reorder Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await vm.saveEdit() } }
                        .disabled(vm.isLoading || vm.editThreshold.isEmpty || vm.editReorderQty.isEmpty)
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.runNow() }
            } label: {
                if vm.isRunningNow {
                    ProgressView().tint(.bizarrePrimary)
                } else {
                    Label("Run now", systemImage: "play.fill")
                }
            }
            .disabled(vm.isRunningNow || vm.rules.filter(\.isTriggered).isEmpty)
            .accessibilityLabel("Run auto-reorder now")
        }
    }

    // MARK: Feedback Banner

    @ViewBuilder
    private var feedbackBanner: some View {
        if let msg = vm.successMessage {
            Text(msg)
                .font(.bizarreBody)
                .padding(12)
                .background(.brandGlass)
                .clipShape(Capsule())
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run { vm.successMessage = nil }
                    }
                }
        }
        if let err = vm.errorMessage {
            Text(err)
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreError)
                .padding(12)
                .background(.brandGlass)
                .clipShape(Capsule())
                .padding(.bottom, 32)
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("No reorder rules")
                .font(.bizarreHeadline)
            Text("Set reorder threshold and quantity on individual inventory items.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - APIClient extension (§6.8 Auto-Reorder Rules)

public struct ReorderRunResponse: Decodable, Sendable {
    public let draftPOsCreated: Int
    enum CodingKeys: String, CodingKey {
        case draftPOsCreated = "draft_pos_created"
    }
}

extension APIClient {
    func listReorderRules() async throws -> [ReorderRule] {
        let resp: APIResponse<[ReorderRule]> = try await get(
            "/api/v1/inventory/reorder-rules"
        )
        return resp.data ?? []
    }

    func runAutoReorder(itemIds: [Int64]) async throws -> Int {
        struct RunRequest: Encodable { let itemIds: [Int64]; enum CodingKeys: String, CodingKey { case itemIds = "item_ids" } }
        let resp: APIResponse<ReorderRunResponse> = try await post(
            "/api/v1/inventory/reorder-rules/run-now",
            body: RunRequest(itemIds: itemIds)
        )
        return resp.data?.draftPOsCreated ?? 0
    }
}
#endif
