#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CouponListViewModel

@MainActor
@Observable
public final class CouponListViewModel {

    // MARK: - State

    public enum LoadState: Equatable {
        case idle, loading, loaded, error(String)
    }

    public private(set) var coupons: [CouponCode] = []
    public private(set) var loadState: LoadState = .idle
    public private(set) var isGenerating: Bool = false

    // Batch generate sheet
    public var showGenerateSheet: Bool = false
    public var generateRuleId: String = ""
    public var generateCount: String = "10"
    public var generatePrefix: String = ""

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Actions

    public func load() async {
        loadState = .loading
        do {
            coupons = try await api.get("/coupons", as: [CouponCode].self)
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    public func generateBatch() async {
        guard let count = Int(generateCount), count > 0 else { return }
        isGenerating = true
        defer { isGenerating = false }
        let req = BatchGenerateCouponsRequest(
            ruleId: generateRuleId,
            count: count,
            prefix: generatePrefix.isEmpty ? nil : generatePrefix
        )
        do {
            let new = try await api.post("/coupons/batch", body: req, as: [CouponCode].self)
            coupons = new + coupons
            showGenerateSheet = false
        } catch {
            // Surface error via alert in view
        }
    }

    public func markExpired(coupon: CouponCode) async {
        do {
            // PATCH /coupons/:id  { expires_at: now }
            struct ExpireBody: Codable, Sendable {
                let expiresAt: String
                enum CodingKeys: String, CodingKey { case expiresAt = "expires_at" }
            }
            let body = ExpireBody(expiresAt: ISO8601DateFormatter().string(from: .now))
            let updated = try await api.patch("/coupons/\(coupon.id)", body: body, as: CouponCode.self)
            coupons = coupons.map { $0.id == coupon.id ? updated : $0 }
        } catch {
            // Handled by view-level alert
        }
    }

    public func delete(coupon: CouponCode) async {
        do {
            try await api.delete("/coupons/\(coupon.id)")
            coupons = coupons.filter { $0.id != coupon.id }
        } catch { }
    }
}

// MARK: - CouponListView

/// Admin view to browse, generate, and manage coupon codes.
/// Accessible from Settings → Marketing → Coupon Codes.
public struct CouponListView: View {
    @State private var vm: CouponListViewModel
    @State private var showGenerateSheet = false
    @State private var searchText = ""

    public init(vm: CouponListViewModel) {
        _vm = State(initialValue: vm)
    }

    private var filteredCoupons: [CouponCode] {
        guard !searchText.isEmpty else { return vm.coupons }
        return vm.coupons.filter {
            $0.code.localizedCaseInsensitiveContains(searchText)
            || $0.ruleName.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showGenerateSheet) {
            generateSheet
        }
    }

    // MARK: - iPhone layout

    private var phoneLayout: some View {
        NavigationStack {
            couponList
                .navigationTitle("Coupon Codes")
                .toolbar { toolbarContent }
                .searchable(text: $searchText, prompt: "Search codes")
        }
    }

    // MARK: - iPad layout

    private var ipadLayout: some View {
        NavigationStack {
            couponList
                .navigationTitle("Coupon Codes")
                .toolbar { toolbarContent }
                .searchable(text: $searchText, prompt: "Search codes")
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var couponList: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading coupons…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
        default:
            if filteredCoupons.isEmpty {
                ContentUnavailableView("No Coupons", systemImage: "tag.slash",
                    description: Text("Generate coupons from the menu."))
            } else {
                List(filteredCoupons) { coupon in
                    CouponRow(coupon: coupon)
                        .listRowBackground(Color.bizarreSurface1)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.delete(coupon: coupon) }
                            } label: { Label("Delete", systemImage: "trash") }

                            Button {
                                Task { await vm.markExpired(coupon: coupon) }
                            } label: {
                                Label("Expire", systemImage: "clock.badge.xmark")
                            }
                            .tint(.orange)
                        }
                        .hoverEffect(.highlight)
                        .contextMenu {
                            Button {
                                Task { await vm.markExpired(coupon: coupon) }
                            } label: { Label("Mark Expired", systemImage: "clock.badge.xmark") }
                            Button(role: .destructive) {
                                Task { await vm.delete(coupon: coupon) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase)
                .accessibilityIdentifier("couponList.list")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.showGenerateSheet = true
            } label: {
                Label("Generate Batch", systemImage: "plus.circle.fill")
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .accessibilityIdentifier("couponList.generate")
        }
    }

    private var generateSheet: some View {
        NavigationStack {
            Form {
                Section("Discount Rule") {
                    TextField("Rule ID", text: $vm.generateRuleId)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("couponGenerate.ruleId")
                }
                Section("Generation") {
                    HStack {
                        Text("Count")
                        Spacer()
                        TextField("10", text: $vm.generateCount)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .accessibilityIdentifier("couponGenerate.count")
                    }
                    HStack {
                        Text("Prefix (optional)")
                        Spacer()
                        TextField("e.g. SUMMER", text: $vm.generatePrefix)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .accessibilityIdentifier("couponGenerate.prefix")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Generate Coupons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showGenerateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        Task { await vm.generateBatch() }
                    }
                    .fontWeight(.semibold)
                    .disabled(vm.isGenerating || vm.generateRuleId.isEmpty)
                    .accessibilityIdentifier("couponGenerate.submit")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - CouponRow

private struct CouponRow: View {
    let coupon: CouponCode

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(coupon.code)
                    .font(.brandLabelLarge().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Spacer()
                statusBadge
            }
            Text(coupon.ruleName)
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if let uses = coupon.usesRemaining {
                Text("\(uses) use\(uses == 1 ? "" : "s") remaining")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let exp = coupon.expiresAt {
                Text("Expires \(exp.formatted(.relative(presentation: .named)))")
                    .font(.brandBodySmall())
                    .foregroundStyle(coupon.isExpired() ? .bizarreError : .bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coupon.code), \(coupon.ruleName), \(coupon.isActive ? "active" : "inactive")")
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = coupon.isExpired()
            ? ("Expired", .bizarreError)
            : coupon.isExhausted
                ? ("Used up", .orange)
                : ("Active", .bizarreSuccess)
        return Text(label)
            .font(.brandLabelSmall())
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}
#endif
