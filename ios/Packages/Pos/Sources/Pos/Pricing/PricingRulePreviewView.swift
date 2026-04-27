#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PricingRulePreviewView (§16 — "Apply to sample cart" simulator)
//
// Admin-facing live-preview panel embedded in `PricingRuleEditorView` (or
// presented as a sheet from `PricingRulesListView`).
//
// The cashier/admin configures a sample cart (items + quantities + prices) and
// sees which rules fire and how much the customer saves. All computation is
// purely local — uses the same `PricingEngine` actor the real POS uses.

// MARK: - SampleCartLine

public struct SampleCartLine: Identifiable {
    public let id: UUID
    public var name: String
    public var sku: String
    public var category: String
    public var unitPriceCents: Int
    public var quantity: Int

    public init(
        id: UUID = .init(),
        name: String,
        sku: String = "",
        category: String = "",
        unitPriceCents: Int,
        quantity: Int = 1
    ) {
        self.id            = id
        self.name          = name
        self.sku           = sku
        self.category      = category
        self.unitPriceCents = unitPriceCents
        self.quantity      = quantity
    }

    var lineTotalCents: Int { unitPriceCents * quantity }
}

// MARK: - PricingRulePreviewViewModel

@MainActor
@Observable
public final class PricingRulePreviewViewModel {

    // MARK: - Sample cart

    public var sampleLines: [SampleCartLine] = [
        SampleCartLine(name: "Sample item", sku: "SAMPLE-001", unitPriceCents: 2000, quantity: 1)
    ]

    public var newLineName: String = ""
    public var newLineSku: String = ""
    public var newLineCategory: String = ""
    public var newLinePriceInput: String = ""   // dollars
    public var newLineQtyInput: String = "1"

    // MARK: - Rules under preview

    public var rules: [PricingRule]

    // MARK: - Result

    public private(set) var result: PricingResult = .empty
    public private(set) var isComputing: Bool = false

    private let engine = PricingEngine()

    public init(rules: [PricingRule] = []) {
        self.rules = rules
    }

    // MARK: - Sample cart management

    public func addLine() {
        guard !newLineName.trimmingCharacters(in: .whitespaces).isEmpty,
              let dollars = Double(newLinePriceInput), dollars > 0,
              let qty = Int(newLineQtyInput), qty > 0 else { return }
        sampleLines.append(SampleCartLine(
            name: newLineName.trimmingCharacters(in: .whitespaces),
            sku: newLineSku.trimmingCharacters(in: .whitespaces),
            category: newLineCategory.trimmingCharacters(in: .whitespaces),
            unitPriceCents: Int((dollars * 100).rounded()),
            quantity: qty
        ))
        newLineName = ""
        newLineSku = ""
        newLineCategory = ""
        newLinePriceInput = ""
        newLineQtyInput = "1"
        Task { await compute() }
    }

    public func removeLine(at offsets: IndexSet) {
        sampleLines.remove(atOffsets: offsets)
        Task { await compute() }
    }

    public func compute() async {
        isComputing = true
        let snapItems = sampleLines.map { line in
            CartItemSnapshot(
                id: line.id,
                sku: line.sku.isEmpty ? nil : line.sku,
                category: line.category.isEmpty ? nil : line.category,
                quantity: line.quantity,
                lineSubtotalCents: line.lineTotalCents
            )
        }
        let subtotal = sampleLines.reduce(0) { $0 + $1.lineTotalCents }
        let snapshot = DiscountCartSnapshot(items: snapItems, subtotalCents: subtotal)
        result = await engine.apply(cart: snapshot, rules: rules, now: .now)
        isComputing = false
    }

    // MARK: - Derived

    var subtotalCents: Int {
        sampleLines.reduce(0) { $0 + $1.lineTotalCents }
    }

    var savingCents: Int { result.totalSavingCents }
    var finalCents: Int { max(0, subtotalCents - savingCents) }
}

// MARK: - PricingRulePreviewView

public struct PricingRulePreviewView: View {

    @Bindable public var vm: PricingRulePreviewViewModel

    public init(vm: PricingRulePreviewViewModel) {
        self.vm = vm
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    sampleCartSection
                    totalsSection
                    adjustmentsSection
                }
                .padding(BrandSpacing.base)
            }
        }
        .navigationTitle("Sample Cart Preview")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.compute() }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Live rule preview")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Add items below to see how rules fire")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreMutedForeground)
            }
            Spacer()
            if vm.isComputing {
                ProgressView()
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Computing preview")
            }
        }
        .padding(BrandSpacing.base)
    }

    private var sampleCartSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("SAMPLE CART")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreMutedForeground)
                .kerning(0.8)

            if vm.sampleLines.isEmpty {
                Text("Add at least one item to preview rules")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreMutedForeground)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(BrandSpacing.md)
            } else {
                ForEach(vm.sampleLines) { line in
                    sampleLineRow(line)
                }
                .onDelete { offsets in vm.removeLine(at: offsets) }
            }

            addLineForm
        }
    }

    private func sampleLineRow(_ line: SampleCartLine) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if !line.sku.isEmpty {
                    Text("SKU: \(line.sku)")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreMutedForeground)
                }
            }
            Spacer()
            Text("×\(line.quantity)")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreMutedForeground)
            Text(CartMath.formatCents(line.lineTotalCents))
                .font(.brandBodyMedium().monospacedDigit())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.sm)
        .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var addLineForm: some View {
        VStack(spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.sm) {
                TextField("Item name", text: $vm.newLineName)
                    .font(.brandBodyMedium())
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("preview.newLineName")
                TextField("$", text: $vm.newLinePriceInput)
                    .keyboardType(.decimalPad)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("preview.newLinePrice")
                TextField("Qty", text: $vm.newLineQtyInput)
                    .keyboardType(.numberPad)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("preview.newLineQty")
            }
            HStack(spacing: BrandSpacing.sm) {
                TextField("SKU (optional)", text: $vm.newLineSku)
                    .font(.brandBodySmall())
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("preview.newLineSku")
                TextField("Category (optional)", text: $vm.newLineCategory)
                    .font(.brandBodySmall())
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("preview.newLineCategory")
                Button {
                    vm.addLine()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.bizarreOrange)
                }
                .disabled(vm.newLineName.isEmpty || vm.newLinePriceInput.isEmpty)
                .accessibilityLabel("Add sample item")
                .accessibilityIdentifier("preview.addLine")
            }
        }
        .padding(BrandSpacing.sm)
        .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private var totalsSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("TOTALS")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreMutedForeground)
                .kerning(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: BrandSpacing.xs) {
                totalRow(label: "Subtotal", cents: vm.subtotalCents, color: .bizarreOnSurface)
                if vm.savingCents > 0 {
                    totalRow(label: "Rules savings", cents: -vm.savingCents, color: .bizarreSuccess)
                }
                Divider()
                totalRow(label: "Final price", cents: vm.finalCents, color: .bizarreOrange, bold: true)
            }
            .padding(BrandSpacing.md)
            .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func totalRow(label: String, cents: Int, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .brandBodyLarge() : .brandBodyMedium())
                .foregroundStyle(color)
            Spacer()
            Text(cents < 0
                 ? "− \(CartMath.formatCents(-cents))"
                 : CartMath.formatCents(cents))
                .font((bold ? Font.brandBodyLarge() : Font.brandBodyMedium()).monospacedDigit())
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(CartMath.formatCents(abs(cents)))")
    }

    @ViewBuilder
    private var adjustmentsSection: some View {
        if !result.adjustments.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("RULE FIRINGS")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreMutedForeground)
                    .kerning(0.8)

                ForEach(Array(result.adjustments.values.flatMap { $0 }.enumerated()), id: \.offset) { _, adj in
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(adj.ruleName)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text(adj.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.brandBodySmall())
                                .foregroundStyle(.bizarreMutedForeground)
                        }
                        Spacer()
                        Text("− \(CartMath.formatCents(adj.savingCents))")
                            .font(.brandBodyMedium().monospacedDigit())
                            .foregroundStyle(.bizarreSuccess)
                    }
                    .padding(BrandSpacing.sm)
                    .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        } else if !vm.sampleLines.isEmpty && !vm.isComputing {
            Text("No pricing rules fired on this cart. Try adjusting quantities or adding items that match a rule.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreMutedForeground)
                .multilineTextAlignment(.center)
                .padding(BrandSpacing.lg)
        }
    }
}

// MARK: - Preview

#Preview("Rule preview — empty") {
    NavigationStack {
        PricingRulePreviewView(vm: PricingRulePreviewViewModel())
    }
    .preferredColorScheme(.dark)
}
#endif
