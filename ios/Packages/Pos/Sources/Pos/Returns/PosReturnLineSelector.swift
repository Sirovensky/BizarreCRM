#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §16.9 Return line model

/// A line item on an invoice that can be selected for return.
/// Includes the restock flag (per §16.9) and qty-to-return stepper.
public struct ReturnableLine: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let description: String
    /// Original quantity on the invoice.
    public let originalQty: Int
    /// Unit price in cents.
    public let unitPriceCents: Int
    /// Whether this line is selected for return.
    public var isSelected: Bool
    /// How many to return (1…originalQty).
    public var qtyToReturn: Int
    /// If true, returned units are restocked in inventory.
    /// If false, items are scrapped / lost (no inventory increment).
    public var restock: Bool

    public init(
        id: Int64,
        description: String,
        originalQty: Int,
        unitPriceCents: Int,
        isSelected: Bool = false,
        qtyToReturn: Int? = nil,
        restock: Bool = true
    ) {
        self.id = id
        self.description = description
        self.originalQty = max(1, originalQty)
        self.unitPriceCents = max(0, unitPriceCents)
        self.isSelected = isSelected
        self.qtyToReturn = min(qtyToReturn ?? max(1, originalQty), max(1, originalQty))
        self.restock = restock
    }

    /// Refund amount for this line in cents.
    public var refundCents: Int { unitPriceCents * qtyToReturn }
}

// MARK: - §16.9 Return line selector view

/// Displays per-line checkboxes + qty steppers + restock toggles for an invoice.
///
/// Shown inside `PosReturnDetailView` when the full invoice detail has been
/// fetched from `GET /api/v1/invoices/:id`.
///
/// iPhone: full-screen list.
/// iPad: inset-grouped with `.hoverEffect` on rows.
public struct PosReturnLineSelector: View {

    @Binding var lines: [ReturnableLine]

    public init(lines: Binding<[ReturnableLine]>) {
        self._lines = lines
    }

    public var body: some View {
        Group {
            if lines.isEmpty {
                emptyState
            } else {
                lineList
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No returnable lines found.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .accessibilityIdentifier("pos.returnLines.empty")
    }

    private var lineList: some View {
        ForEach($lines) { $line in
            lineRow(line: $line)
        }
    }

    private func lineRow(line: Binding<ReturnableLine>) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            // Selection + description
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                Toggle("", isOn: line.isSelected)
                    .labelsHidden()
                    .tint(.bizarreOrange)
                    .frame(width: 44)
                    .accessibilityLabel("Return \(line.wrappedValue.description)")
                    .accessibilityIdentifier("pos.returnLines.select.\(line.wrappedValue.id)")

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(line.wrappedValue.description)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    Text(CartMath.formatCents(line.wrappedValue.unitPriceCents) + " each · " + "\(line.wrappedValue.originalQty) ordered")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Text(CartMath.formatCents(line.wrappedValue.refundCents))
                    .font(.brandTitleSmall())
                    .monospacedDigit()
                    .foregroundStyle(line.wrappedValue.isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
            }

            // Per-line controls — only when selected
            if line.wrappedValue.isSelected {
                HStack(spacing: BrandSpacing.base) {
                    // Qty stepper
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Qty to return")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Stepper(
                            value: line.qtyToReturn,
                            in: 1...line.wrappedValue.originalQty
                        ) {
                            Text("\(line.wrappedValue.qtyToReturn) of \(line.wrappedValue.originalQty)")
                                .font(.brandBodyMedium())
                                .monospacedDigit()
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        .accessibilityIdentifier("pos.returnLines.qty.\(line.wrappedValue.id)")
                    }

                    Spacer()

                    // Restock toggle
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Restock")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Toggle("Restock", isOn: line.restock)
                            .labelsHidden()
                            .tint(.bizarreSuccess)
                            .accessibilityLabel("Restock \(line.wrappedValue.description)")
                            .accessibilityIdentifier("pos.returnLines.restock.\(line.wrappedValue.id)")
                    }
                }
                .padding(.leading, 44 + BrandSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Restock hint
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: line.wrappedValue.restock ? "arrow.uturn.left.circle" : "trash.circle")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(line.wrappedValue.restock
                         ? "Returned to inventory"
                         : "Marked as damaged / scrap")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.leading, 44 + BrandSpacing.md)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .animation(.easeInOut(duration: 0.18), value: line.wrappedValue.isSelected)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Summary bar

/// Shows selected lines count + total refund. Displayed above the Submit CTA.
public struct PosReturnSummaryBar: View {
    public let selectedLines: [ReturnableLine]
    public let managerPinThresholdCents: Int

    public init(selectedLines: [ReturnableLine], managerPinThresholdCents: Int = 5_000) {
        self.selectedLines = selectedLines
        self.managerPinThresholdCents = managerPinThresholdCents
    }

    public var totalRefundCents: Int {
        selectedLines.filter(\.isSelected).map(\.refundCents).reduce(0, +)
    }

    public var requiresManagerPin: Bool {
        totalRefundCents > managerPinThresholdCents
    }

    public var body: some View {
        if !selectedLines.filter(\.isSelected).isEmpty {
            HStack(spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedLines.filter(\.isSelected).count) line(s) selected")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("Refund total: " + CartMath.formatCents(totalRefundCents))
                        .font(.brandTitleMedium())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOrange)
                }
                Spacer()
                if requiresManagerPin {
                    Label("Manager PIN required", systemImage: "lock.shield.fill")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityIdentifier("pos.returnSummary.pinRequired")
                }
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Return summary: \(selectedLines.filter(\.isSelected).count) lines, \(CartMath.formatCents(totalRefundCents)) total."
                + (requiresManagerPin ? " Manager PIN required." : "")
            )
        }
    }
}

// MARK: - Tests-visible helpers

extension ReturnableLine {
    /// Build a test set of lines from an invoice's line items.
    public static func from(invoiceLines: [InvoiceLineItem]) -> [ReturnableLine] {
        invoiceLines.map { line in
            ReturnableLine(
                id: line.id,
                description: line.name ?? line.description ?? "Item",
                originalQty: line.qty,
                unitPriceCents: line.unitPriceCents
            )
        }
    }
}

// MARK: - Invoice line item (lightweight DTO for the returns view)

/// Minimal invoice line projection sufficient for the returns flow.
/// Fetched via `GET /api/v1/invoices/:id` — the full invoice detail includes
/// `lines` as a nested array.
public struct InvoiceLineItem: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String?
    public let description: String?
    public let qty: Int
    public let unitPriceCents: Int

    public init(id: Int64, name: String?, description: String?, qty: Int, unitPriceCents: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.qty = qty
        self.unitPriceCents = unitPriceCents
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, qty
        case unitPrice = "unit_price"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        qty = max(1, (try c.decodeIfPresent(Int.self, forKey: .qty)) ?? 1)
        let dollars = try c.decodeIfPresent(Decimal.self, forKey: .unitPrice) ?? 0
        unitPriceCents = Int(NSDecimalNumber(decimal: dollars * 100).doubleValue.rounded())
    }
}

// MARK: - Preview

#Preview("Line selector") {
    @Previewable @State var lines: [ReturnableLine] = [
        ReturnableLine(id: 1, description: "iPhone 15 Screen Replacement", originalQty: 1, unitPriceCents: 14999),
        ReturnableLine(id: 2, description: "Tempered Glass (3-pack)", originalQty: 2, unitPriceCents: 2499),
        ReturnableLine(id: 3, description: "USB-C Cable", originalQty: 3, unitPriceCents: 1299),
    ]
    return NavigationStack {
        List {
            Section("Select lines to return") {
                PosReturnLineSelector(lines: $lines)
            }
            Section {
                PosReturnSummaryBar(selectedLines: lines)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Process Return")
        .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
}
#endif
