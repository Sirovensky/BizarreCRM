import SwiftUI
import Core
import DesignSystem

// MARK: - ViewModel
// NOTE: No server /coupons endpoint exists. This is client-only local state.
// When the server exposes coupon routes, replace the in-memory store with
// real APIClient calls and wire CouponCode.serverRowId.

@MainActor
@Observable
public final class CouponCodesViewModel {
    public private(set) var coupons: [CouponCode] = []
    public var showingCreate = false
    public var editingCoupon: CouponCode? = nil
    public var confirmDelete: CouponCode? = nil
    private(set) var errorMessage: String? = nil

    public init() {}

    public func add(_ coupon: CouponCode) {
        coupons = coupons + [coupon]
    }

    public func update(_ coupon: CouponCode) {
        coupons = coupons.map { $0.id == coupon.id ? coupon : $0 }
    }

    public func delete(id: String) {
        coupons = coupons.filter { $0.id != id }
    }

    public func toggleActive(id: String) {
        coupons = coupons.map { c in
            c.id == id ? CouponCode(
                id: c.id, code: c.code,
                discountType: c.discountType, discountValue: c.discountValue,
                maxUses: c.maxUses, usedCount: c.usedCount,
                expiresAt: c.expiresAt, isActive: !c.isActive
            ) : c
        }
    }
}

// MARK: - List view

/// Coupon code manager (inline CRUD).
/// Displayed on iPad as a sidebar panel within the campaign detail; on iPhone as
/// a pushed NavigationStack destination.
public struct CouponCodesView: View {
    @State private var vm: CouponCodesViewModel
    @State private var showCreate = false

    public init(vm: CouponCodesViewModel? = nil) {
        _vm = State(wrappedValue: vm ?? CouponCodesViewModel())
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Coupon Codes")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .toolbar { addButton }
        .sheet(isPresented: $showCreate) {
            CouponEditorSheet(coupon: nil) { coupon in
                vm.add(coupon)
            }
        }
        .sheet(item: $vm.editingCoupon) { coupon in
            CouponEditorSheet(coupon: coupon) { updated in
                vm.update(updated)
            }
        }
        .confirmationDialog(
            "Delete \"\(vm.confirmDelete?.code ?? "")\"?",
            isPresented: Binding(
                get: { vm.confirmDelete != nil },
                set: { if !$0 { vm.confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let c = vm.confirmDelete { vm.delete(id: c.id) }
                vm.confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { vm.confirmDelete = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.coupons.isEmpty {
            emptyState
        } else {
            couponList
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No coupon codes")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Create codes to share with customers.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button {
                showCreate = true
            } label: {
                Label("Add coupon", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("marketing.coupons.add.empty")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var couponList: some View {
        List {
            ForEach(vm.coupons) { coupon in
                CouponRow(coupon: coupon)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            vm.confirmDelete = coupon
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            vm.editingCoupon = coupon
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.bizarreTeal)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            vm.toggleActive(id: coupon.id)
                        } label: {
                            Label(
                                coupon.isActive ? "Deactivate" : "Activate",
                                systemImage: coupon.isActive ? "pause.circle" : "play.circle"
                            )
                        }
                        .tint(coupon.isActive ? .bizarreWarning : .bizarreSuccess)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                    .contextMenu {
                        Button { vm.editingCoupon = coupon } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button { vm.toggleActive(id: coupon.id) } label: {
                            Label(
                                coupon.isActive ? "Deactivate" : "Activate",
                                systemImage: coupon.isActive ? "pause.circle" : "play.circle"
                            )
                        }
                        Divider()
                        Button(role: .destructive) { vm.confirmDelete = coupon } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showCreate = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add coupon code")
                .accessibilityIdentifier("marketing.coupons.add")
                #if canImport(UIKit)
                .keyboardShortcut("N", modifiers: .command)
                #endif
        }
    }
}

// MARK: - Row

private struct CouponRow: View {
    let coupon: CouponCode

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 18))
                .foregroundStyle(coupon.isActive ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    Text(coupon.code)
                        .font(.brandMono(size: 14))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                    if !coupon.isActive {
                        Text("Inactive")
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.xs)
                            .padding(.vertical, 1)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .background(Color.bizarreSurface2, in: Capsule())
                    }
                }
                HStack(spacing: BrandSpacing.sm) {
                    Text(coupon.displayDiscount)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let max = coupon.maxUses {
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("\(coupon.usedCount) / \(max) uses")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let exp = coupon.expiresAt {
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("Exp \(exp, style: .date)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(exp < Date() ? .bizarreError : .bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coupon.code), \(coupon.displayDiscount)\(coupon.isActive ? "" : ", inactive")")
    }
}

// MARK: - Editor sheet

struct CouponEditorSheet: View {
    let existingCoupon: CouponCode?
    let onSave: (CouponCode) -> Void

    @State private var code: String
    @State private var discountType: CouponDiscountType
    @State private var discountValue: Double
    @State private var maxUses: String
    @State private var expiresAt: Date?
    @State private var hasExpiry = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    init(coupon: CouponCode?, onSave: @escaping (CouponCode) -> Void) {
        self.existingCoupon = coupon
        self.onSave = onSave
        _code = State(wrappedValue: coupon?.code ?? "")
        _discountType = State(wrappedValue: coupon?.discountType ?? .percent)
        _discountValue = State(wrappedValue: coupon?.discountValue ?? 10)
        _maxUses = State(wrappedValue: coupon?.maxUses.map { String($0) } ?? "")
        _hasExpiry = State(wrappedValue: coupon?.expiresAt != nil)
        _expiresAt = State(wrappedValue: coupon?.expiresAt ?? Date().addingTimeInterval(86400 * 30))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Code") {
                        TextField("e.g. SUMMER20", text: $code)
                            .font(.brandMono(size: 14))
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.characters)
                            #endif
                            .accessibilityLabel("Coupon code")
                            .accessibilityIdentifier("marketing.coupon.code")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    Section("Discount") {
                        Picker("Type", selection: $discountType) {
                            ForEach(CouponDiscountType.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .accessibilityLabel("Discount type")

                        if discountType != .freeItem {
                            HStack {
                                Text(discountType == .percent ? "Percentage" : "Amount ($)")
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                Spacer()
                                TextField("0", value: $discountValue, format: .number)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                    .accessibilityLabel(discountType == .percent ? "Percentage" : "Dollar amount")
                            }
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    Section("Limits") {
                        HStack {
                            Text("Max uses")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            TextField("Unlimited", text: $maxUses)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                                #if canImport(UIKit)
                                .keyboardType(.numberPad)
                                #endif
                                .accessibilityLabel("Maximum uses")
                        }
                        Toggle("Has expiry", isOn: $hasExpiry)
                            .accessibilityLabel("Coupon has expiry date")
                        if hasExpiry {
                            DatePicker(
                                "Expires",
                                selection: Binding(
                                    get: { expiresAt ?? Date().addingTimeInterval(86400 * 30) },
                                    set: { expiresAt = $0 }
                                ),
                                in: Date()...,
                                displayedComponents: .date
                            )
                            .accessibilityLabel("Expiry date")
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    if let err = errorMessage {
                        Section {
                            Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                        .listRowBackground(Color.bizarreError.opacity(0.1))
                    }
                }
                .scrollContentBackground(.hidden)
                #if canImport(UIKit)
                .background(Color.bizarreSurfaceBase)
                #endif
            }
            .navigationTitle(existingCoupon == nil ? "New Coupon" : "Edit Coupon")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("marketing.coupon.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            errorMessage = "Coupon code is required."
            return
        }
        guard trimmed.count <= 50 else {
            errorMessage = "Code must be 50 characters or fewer."
            return
        }
        let maxUsesInt: Int? = maxUses.isEmpty ? nil : Int(maxUses)
        let coupon = CouponCode(
            id: existingCoupon?.id ?? UUID().uuidString,
            code: trimmed,
            discountType: discountType,
            discountValue: discountValue,
            maxUses: maxUsesInt,
            usedCount: existingCoupon?.usedCount ?? 0,
            expiresAt: hasExpiry ? expiresAt : nil,
            isActive: existingCoupon?.isActive ?? true
        )
        onSave(coupon)
        dismiss()
    }
}
