#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRepairQuoteView (Frame 1d)
//
// Step 3: Diagnostic notes + parts/labor checklist with running estimate.
//
// Pre-population: When Agent F's ServiceBundleResolver is available the
// coordinator can inject pre-populated lines; this view treats them as
// read-write toggles so the cashier can exclude unrelevant items.
//
// Server wiring: diagnostic notes are persisted via
// POST /api/v1/tickets/:id/notes (type=diagnostic) in commitQuoteStep().

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

    static func formatCurrency(cents: Int) -> String {
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
        List {
            progressSection

            diagnosticNotesSection

            partsLaborSection

            estimateSection
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            ctaBar
        }
        .navigationTitle(RepairStep.diagnosticQuote.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    vm.commitToDraft(coordinator: coordinator)
                    coordinator.goBack()
                }
                .accessibilityLabel("Back to describe issue")
                .accessibilityIdentifier("repairFlow.quote.back")
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
            // Restore from draft on back-navigation.
            vm.diagnosticNotes = coordinator.draft.diagnosticNotes
            vm.lines = coordinator.draft.quoteLines
        }
    }

    // MARK: - Sections

    private var progressSection: some View {
        Section {
            ProgressView(value: RepairStep.diagnosticQuote.progressPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(.bizarreOrange)
                .accessibilityLabel(RepairStep.diagnosticQuote.accessibilityDescription)
                .accessibilityValue("\(Int(RepairStep.diagnosticQuote.progressPercent))%")
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var diagnosticNotesSection: some View {
        Section("Diagnostic notes") {
            TextEditor(text: $vm.diagnosticNotes)
                .frame(minHeight: 100)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Diagnostic notes")
                .accessibilityHint("Technical notes about the issue found during diagnosis")
                .accessibilityIdentifier("repairFlow.quote.diagnosticNotes")
        }
    }

    @ViewBuilder
    private var partsLaborSection: some View {
        Section {
            if vm.lines.isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("No parts or labor added yet.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.vertical, BrandSpacing.sm)
                // TODO: pre-populate via Agent F ServiceBundleResolver when available
                // Call: ServiceBundleResolver.shared.paired(for: serviceItemId, device: customerAsset)
                .accessibilityLabel("No parts or labor added. Tap + to add items.")
            } else {
                ForEach(vm.lines) { line in
                    quoteLineRow(line)
                }
                .onDelete { offsets in
                    vm.removeLine(at: offsets)
                }
            }
        } header: {
            HStack {
                Text("Parts & labor")
                    .font(.brandLabelLarge())
                Spacer(minLength: 0)
                Text("Included")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private func quoteLineRow(_ line: RepairQuoteLine) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Button {
                vm.toggleLine(line)
                BrandHaptics.tap()
            } label: {
                Image(systemName: line.isIncluded ? "checkmark.square.fill" : "square")
                    .foregroundStyle(line.isIncluded ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.isIncluded ? "Included: \(line.name)" : "Excluded: \(line.name)")
            .accessibilityHint("Tap to toggle")

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(line.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(line.isIncluded ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                    .strikethrough(!line.isIncluded)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                if line.isPrePopulated {
                    Text("Suggested")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }
            }

            Spacer(minLength: 0)

            Text(PosRepairQuoteViewModel.formatCurrency(cents: line.priceCents))
                .font(.brandLabelLarge().monospacedDigit())
                .foregroundStyle(line.isIncluded ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("repairFlow.quote.line.\(line.id.uuidString.prefix(8))")
    }

    private var estimateSection: some View {
        Section {
            HStack {
                Text("Running estimate")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Text(vm.estimateFormatted)
                    .font(.brandTitleMedium().monospacedDigit())
                    .foregroundStyle(.bizarreOrange)
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Running estimate: \(vm.estimateFormatted)")
        }
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
        VStack(spacing: BrandSpacing.xs) {
            if let error = coordinator.errorMessage {
                Text(error)
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.md)
            }

            HStack(spacing: BrandSpacing.sm) {
                Button {
                    vm.commitToDraft(coordinator: coordinator)
                    BrandHaptics.tapMedium()
                } label: {
                    Text("Save as quote")
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .accessibilityLabel("Save as draft quote")
                .accessibilityIdentifier("repairFlow.quote.saveQuote")

                Button {
                    vm.commitToDraft(coordinator: coordinator)
                    coordinator.advance()
                    BrandHaptics.tapMedium()
                } label: {
                    HStack {
                        if coordinator.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Continue to deposit")
                                .font(.brandTitleSmall())
                            Image(systemName: "chevron.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(coordinator.isLoading)
                .accessibilityLabel("Continue to deposit")
                .accessibilityHint("Advances to step 4 of 4")
                .accessibilityIdentifier("repairFlow.quote.continue")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.bottom, BrandSpacing.md)
        .background(.ultraThinMaterial)
    }
}
#endif
