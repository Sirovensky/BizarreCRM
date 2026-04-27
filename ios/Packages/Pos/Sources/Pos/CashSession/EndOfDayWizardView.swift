#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §39.4 — End-of-day wizard. Manager-only flow that walks through 7 steps
/// before locking the POS terminal.
///
/// Permissions: manager-only; cashier sees "Need manager" alert.
///
/// iPhone: full-screen `NavigationStack` with step progress bar.
/// iPad: centred `.large` sheet (the wider canvas lets all steps show
///       at once as a sidebar + detail split).
///
/// The wizard can be aborted mid-flow; completed steps are stamped in the
/// local audit log via `PosAuditLogStore` even if the wizard is aborted.
/// Resuming re-enters from the last incomplete step.
@MainActor
public struct EndOfDayWizardView: View {

    @State private var vm = EndOfDayWizardViewModel()
    @State private var showCSVExporter: Bool = false
    @State private var showAbortAlert: Bool = false

    @Environment(\.dismiss) private var dismiss

    public let sampleTransactions: [ReconciliationRow]

    public init(sampleTransactions: [ReconciliationRow] = []) {
        self.sampleTransactions = sampleTransactions
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    phoneLayout
                } else {
                    padLayout
                }
            }
            .navigationTitle("End of Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .alert("Abort end-of-day?", isPresented: $showAbortAlert) {
                Button("Abort", role: .destructive) {
                    vm.abort()
                    dismiss()
                }
                Button("Continue", role: .cancel) {}
            } message: {
                Text("Completed steps are saved. You can resume later.")
            }
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: CSVDocument(data: vm.csvData ?? Data()),
            contentType: .commaSeparatedText,
            defaultFilename: vm.csvFilename
        ) { result in
            switch result {
            case .success(let url):
                AppLog.pos.info("Reconciliation CSV exported to \(url.lastPathComponent, privacy: .public)")
            case .failure(let err):
                AppLog.pos.error("CSV export failed: \(err.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.sm)

            if case .complete = vm.wizardState {
                completionView
            } else {
                stepList
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Sidebar: all steps at a glance
            stepsSidebar
                .frame(width: 260)
            Divider()
            // Detail: current step action
            if case .complete = vm.wizardState {
                completionView
            } else if let step = vm.currentStep {
                stepDetailPanel(step)
            } else {
                completionView
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let total = EndOfDayStep.allCases.count
        let done = vm.completedSteps.count + vm.skippedSteps.count
        return VStack(spacing: BrandSpacing.xs) {
            ProgressView(value: Double(done), total: Double(total))
                .tint(.bizarreOrange)
                .accessibilityIdentifier("eod.wizard.progress")
            Text("\(done) of \(total) steps complete")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Step list (phone)

    private var stepList: some View {
        List(EndOfDayStep.allCases, id: \.rawValue) { step in
            stepRow(step)
                .listRowBackground(Color.bizarreSurface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Sidebar (iPad)

    private var stepsSidebar: some View {
        List(EndOfDayStep.allCases, id: \.rawValue) { step in
            sidebarRow(step)
                .listRowBackground(
                    vm.currentStep == step
                    ? Color.bizarreOrange.opacity(0.12)
                    : Color.bizarreSurface1
                )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Row helpers

    private func stepRow(_ step: EndOfDayStep) -> some View {
        HStack(spacing: BrandSpacing.md) {
            stepStatusIcon(step)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BrandSpacing.xs) {
                    Text(step.title)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if step.isOptional {
                        Text("Optional")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Text(step.subtitle)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }
            Spacer()
            stepActions(step)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("eod.wizard.step.\(step.rawValue)")
    }

    private func sidebarRow(_ step: EndOfDayStep) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            stepStatusIcon(step)
            Text(step.title)
                .font(.brandBodyMedium())
                .foregroundStyle(
                    vm.currentStep == step ? .bizarreOrange : .bizarreOnSurface
                )
                .lineLimit(1)
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    @ViewBuilder
    private func stepStatusIcon(_ step: EndOfDayStep) -> some View {
        if vm.completedSteps.contains(step) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreSuccess)
                .accessibilityLabel("Completed")
        } else if vm.skippedSteps.contains(step) {
            Image(systemName: "forward.circle")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityLabel("Skipped")
        } else if vm.currentStep == step {
            Image(systemName: step.icon)
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Current step")
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.bizarreOutline)
                .accessibilityLabel("Pending")
        }
    }

    @ViewBuilder
    private func stepActions(_ step: EndOfDayStep) -> some View {
        if !vm.completedSteps.contains(step) && !vm.skippedSteps.contains(step) {
            HStack(spacing: BrandSpacing.sm) {
                Button("Done") { vm.markCompleted(step) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("eod.wizard.done.\(step.rawValue)")

                if step.isOptional {
                    Button("Skip") { vm.skipStep(step) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("eod.wizard.skip.\(step.rawValue)")
                }
            }
        }
    }

    // MARK: - Step detail panel (iPad)

    private func stepDetailPanel(_ step: EndOfDayStep) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                Image(systemName: step.icon)
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOrange)
                    .padding(.top, BrandSpacing.xl)
                    .accessibilityHidden(true)

                VStack(spacing: BrandSpacing.sm) {
                    Text(step.title)
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(step.subtitle)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.xl)
                }

                // CSV export for the reconciliation step lives inline on the
                // closeShifts step (first step, naturally).
                if step == .closeCashShifts {
                    csvExportSection
                }

                HStack(spacing: BrandSpacing.md) {
                    Button("Mark done") { vm.markCompleted(step) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.bizarreOrange)
                        .accessibilityIdentifier("eod.wizard.doneDetail.\(step.rawValue)")

                    if step.isOptional {
                        Button("Skip") { vm.skipStep(step) }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityIdentifier("eod.wizard.skipDetail.\(step.rawValue)")
                    }
                }
                .padding(.horizontal, BrandSpacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - CSV export section

    private var csvExportSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Reconciliation CSV")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button {
                vm.generateCSV(transactions: sampleTransactions)
                showCSVExporter = true
            } label: {
                Label("Export daily CSV", systemImage: "tablecells")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("eod.wizard.exportCSV")
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, BrandSpacing.xl)
    }

    // MARK: - Completion view

    private var completionView: some View {
        VStack(spacing: BrandSpacing.xl) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreOrange)
                .padding(.top, BrandSpacing.xxl)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("End of Day Complete")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("All steps finished. The POS is locked for tonight.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }

            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("eod.wizard.close")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if case .complete = vm.wizardState {
                EmptyView()
            } else {
                Button("Abort") { showAbortAlert = true }
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("eod.wizard.abort")
            }
        }
    }
}

// MARK: - CSV file document

import UniformTypeIdentifiers

/// `FileDocument` wrapper so `.fileExporter` can write the CSV.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

#Preview("End of Day — Phone") {
    EndOfDayWizardView(sampleTransactions: [
        ReconciliationRow(
            dateTime: Date(),
            invoiceId: 1001,
            lineDescription: "iPhone 15 Screen",
            qty: 1,
            unitPriceCents: 14999,
            lineTotalCents: 14999,
            tenderMethod: "card",
            tenderAmountCents: 14999
        )
    ])
    .preferredColorScheme(.dark)
}
#endif
