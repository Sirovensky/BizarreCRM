#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRepairQuoteView (Frame 1d)
//
// Step 3: Diagnostic notes + parts/labor checklist with running estimate.
//
// Visual spec: scroll view with card-style rows (NOT List.insetGrouped),
// running estimate hero card with large price, split footer CTA.
// Progress bar pinned below nav bar at 66%.

@MainActor
@Observable
public final class PosRepairQuoteViewModel {

    // MARK: - State

    public var diagnosticNotes: String = ""
    public var lines: [RepairQuoteLine] = []

    // MARK: - Derived

    public var estimateCents: Int {
        lines.filter { $0.isIncluded }.reduce(0) { $0 + $1.priceCents }
    }

    public var estimateFormatted: String {
        Self.formatCurrency(cents: estimateCents)
    }

    public var includedCount: Int {
        lines.filter { $0.isIncluded }.count
    }

    // MARK: - Actions

    public func toggleLine(_ line: RepairQuoteLine) {
        guard let idx = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[idx] = line.toggled()
    }

    public func addLine(name: String, priceCents: Int) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newLine = RepairQuoteLine(name: name, priceCents: priceCents)
        lines.append(newLine)
    }

    public func removeLine(at offsets: IndexSet) {
        lines.remove(atOffsets: offsets)
    }

    public func commitToDraft(coordinator: PosRepairFlowCoordinator) {
        coordinator.setQuote(diagnosticNotes: diagnosticNotes, lines: lines)
    }

    // MARK: - Helpers

    public static func formatCurrency(cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}

// MARK: - View

public struct PosRepairQuoteView: View {

    @Bindable private var coordinator: PosRepairFlowCoordinator
    @State private var vm = PosRepairQuoteViewModel()

    @State private var showingAddLine: Bool = false
    @State private var newLineName: String = ""
    @State private var newLinePriceText: String = ""

    public init(coordinator: PosRepairFlowCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Step 3/4 progress bar pinned below nav (66%)
            // Gradient: primary (orange) → primary-bright, left → right per mockup.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.bizarreOnSurface.opacity(0.06))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.bizarreOrange, Color.bizarreOrangeBright],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.66)
                }
            }
            .frame(height: 3)
            .accessibilityLabel("Step 3 of 4, 66% complete")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    diagnosticNotesSection
                        .padding(.top, 12)

                    partsLaborSection
                        .padding(.top, 8)

                    estimateHeroCard
                        .padding(.top, 10)
                        .padding(.horizontal, 16)

                    Spacer().frame(height: 16)
                }
                .padding(.bottom, 100) // room for split CTA
            }
        }
        .safeAreaInset(edge: .bottom) {
            ctaBar
        }
        .navigationTitle("Quote · Step 3/4")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Auto-save")
                    .font(.caption)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.bizarreSurface1, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddLine = true
                } label: {
                    Label("Add line", systemImage: "plus")
                }
                .accessibilityLabel("Add parts/labor line")
                .accessibilityIdentifier("repairFlow.quote.addLine")
            }
        }
        .sheet(isPresented: $showingAddLine) {
            addLineSheet
        }
        .onAppear {
            vm.diagnosticNotes = coordinator.draft.diagnosticNotes
            vm.lines = coordinator.draft.quoteLines
        }
    }

    // MARK: - Sections

    private var diagnosticNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagnostic notes")
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .padding(.horizontal, 16)

            TextEditor(text: $vm.diagnosticNotes)
                .frame(minHeight: 60)
                .font(.system(size: 13))
                .foregroundStyle(.bizarreOnSurface)
                .padding(10)
                .background(Color.bizarreOnSurface.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 1))
                .padding(.horizontal, 16)
                .accessibilityLabel("Diagnostic notes")
                .accessibilityIdentifier("repairFlow.quote.diagnosticNotes")
        }
    }

    @ViewBuilder
    private var partsLaborSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested parts + labor")
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .padding(.horizontal, 16)

            if vm.lines.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("No parts or labor added yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .accessibilityLabel("No parts or labor added. Tap + to add items.")
            } else {
                VStack(spacing: 6) {
                    ForEach(vm.lines) { line in
                        quoteLineCard(line)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func quoteLineCard(_ line: RepairQuoteLine) -> some View {
        let isIncluded = line.isIncluded
        return HStack(spacing: 10) {
            // Checkbox
            Button {
                vm.toggleLine(line)
                BrandHaptics.tap()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isIncluded ? Color.bizarreOrange : Color.clear)
                        .frame(width: 22, height: 22)
                    if isIncluded {
                        Text("✓")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.7))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.bizarreOnSurface.opacity(0.2), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isIncluded ? "Included" : "Excluded")

            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isIncluded ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                    .strikethrough(!isIncluded)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                if let subtitle = lineSubtitle(line) {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(
                            subtitle.contains("low") ? Color.bizarreWarning : Color.bizarreOnSurfaceMuted
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(PosRepairQuoteViewModel.formatCurrency(cents: line.priceCents))
                .font(.custom("BarlowCondensed-SemiBold", size: 16).monospacedDigit())
                .foregroundStyle(isIncluded ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bizarreSurface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isIncluded
                                ? Color.bizarreOrange.opacity(0.35)
                                : Color.bizarreOnSurface.opacity(0.07),
                            lineWidth: isIncluded ? 1.5 : 1
                        )
                )
        )
        .opacity(isIncluded ? 1 : 0.65)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("repairFlow.quote.line.\(line.id.uuidString.prefix(8))")
    }

    /// Running estimate hero card — large price + gradient background (mockup 1d).
    private var estimateHeroCard: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimate · \(vm.includedCount) item\(vm.includedCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                Text("+tax · final at pickup")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            Spacer()
            // Large price display (30pt font-weight 800, tabular nums per mockup)
            Text(vm.estimateFormatted)
                .font(.system(size: 30, weight: .heavy).monospacedDigit())
                .kerning(-0.6)
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityLabel("Estimate: \(vm.estimateFormatted)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Estimate hero card background: surface-solid base + tinted gradient overlay
        // Matches mockup: background: linear-gradient(...), var(--surface-solid) + border.
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.bizarreSurface1)
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: Color.bizarreOrange.opacity(0.10), location: 0),
                            .init(color: Color.bizarreOrange.opacity(0.02), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bizarreOrange.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Add line sheet

    private var addLineSheet: some View {
        NavigationStack {
            Form {
                Section("Line description") {
                    TextField("e.g. iPhone 14 screen replacement", text: $newLineName)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("repairFlow.addLine.name")
                }
                Section("Price") {
                    HStack {
                        Text("$")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        TextField("0.00", text: $newLinePriceText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("repairFlow.addLine.price")
                    }
                }
            }
            .navigationTitle("Add line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newLineName = ""
                        newLinePriceText = ""
                        showingAddLine = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let cents = Int((Double(newLinePriceText) ?? 0) * 100)
                        vm.addLine(name: newLineName, priceCents: cents)
                        newLineName = ""
                        newLinePriceText = ""
                        showingAddLine = false
                        BrandHaptics.success()
                    }
                    .disabled(newLineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("repairFlow.addLine.confirm")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - CTA bar

    private var ctaBar: some View {
        VStack(spacing: 8) {
            if let error = coordinator.errorMessage {
                Text(error)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // "Save as quote" secondary button — full width above primary
            Button {
                vm.commitToDraft(coordinator: coordinator)
                BrandHaptics.tapMedium()
            } label: {
                Text("Save as quote")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(Color.bizarreOnSurface)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save as draft quote")
            .accessibilityIdentifier("repairFlow.quote.saveQuote")

            // Primary CTA
            Button {
                vm.commitToDraft(coordinator: coordinator)
                coordinator.advance()
                BrandHaptics.tapMedium()
            } label: {
                HStack(spacing: 6) {
                    if coordinator.isLoading {
                        ProgressView().tint(Color.bizarreOnPrimary)
                    } else {
                        Text("Continue → deposit")
                            .font(.subheadline.weight(.bold))
                        Text("›")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    coordinator.isLoading
                        ? Color.bizarreOrange.opacity(0.4)
                        : Color.bizarreOrange,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(Color.bizarreOnPrimary)
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isLoading)
            .accessibilityLabel("Continue to deposit")
            .accessibilityHint("Advances to step 4 of 4")
            .accessibilityIdentifier("repairFlow.quote.continue")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func lineSubtitle(_ line: RepairQuoteLine) -> String? {
        // Prefer the explicit subtitle (stock info, time estimate, etc.).
        // Fall back to "Suggested" for pre-populated items with no subtitle.
        if let s = line.subtitle, !s.isEmpty { return s }
        if line.isPrePopulated { return "Suggested" }
        return nil
    }
}
#endif
