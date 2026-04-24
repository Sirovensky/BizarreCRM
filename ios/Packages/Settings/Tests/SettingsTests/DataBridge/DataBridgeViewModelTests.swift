import Testing
import Foundation
@testable import Settings

// MARK: - Stub providers

private actor StubImportProvider: ImportSummaryProvider {
    let summary: ImportSummary
    init(_ summary: ImportSummary) { self.summary = summary }
    func fetchSummary() async -> ImportSummary { summary }
}

private actor FailingImportProvider: ImportSummaryProvider {
    func fetchSummary() async -> ImportSummary {
        // Simulate a delay then return empty; providers don't throw, so empty
        // is the worst case (the VM maps this to neutral state).
        ImportSummary()
    }
}

private actor StubExportProvider: ExportSummaryProvider {
    let summary: ExportSummary
    init(_ summary: ExportSummary) { self.summary = summary }
    func fetchSummary() async -> ExportSummary { summary }
}

// MARK: - ImportStatusSummaryViewModel Tests

@Suite("ImportStatusSummaryViewModel")
struct ImportStatusSummaryViewModelTests {

    @Test("Initial state is idle")
    @MainActor
    func initialStateIsIdle() {
        let vm = ImportStatusSummaryViewModel(provider: nil)
        guard case .idle = vm.state else {
            Issue.record("Expected .idle, got \(vm.state)")
            return
        }
    }

    @Test("Nil provider transitions to loaded with empty summary")
    @MainActor
    func nilProviderLoadsEmpty() async {
        let vm = ImportStatusSummaryViewModel(provider: nil)
        await vm.load()
        guard case .loaded(let summary) = vm.state else {
            Issue.record("Expected .loaded after nil-provider load")
            return
        }
        #expect(summary == ImportSummary())
    }

    @Test("Nil provider: pillHue is neutral")
    @MainActor
    func nilProviderPillHueIsNeutral() async {
        let vm = ImportStatusSummaryViewModel(provider: nil)
        await vm.load()
        #expect(vm.pillHue == .neutral)
    }

    @Test("Nil provider: hasActiveJob is false")
    @MainActor
    func nilProviderHasNoActiveJob() async {
        let vm = ImportStatusSummaryViewModel(provider: nil)
        await vm.load()
        #expect(!vm.hasActiveJob)
    }

    @Test("Success result sets pillHue to success")
    @MainActor
    func successResultPillHueIsSuccess() async {
        let summary = ImportSummary(
            lastResult: .success(entityCount: 42, at: Date()),
            activeJobCount: 0
        )
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.pillHue == .success)
    }

    @Test("Success result pillLabel mentions record count")
    @MainActor
    func successResultPillLabelMentionsCount() async {
        let summary = ImportSummary(
            lastResult: .success(entityCount: 42, at: Date()),
            activeJobCount: 0
        )
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.pillLabel.contains("42"))
    }

    @Test("Failure result sets pillHue to failure")
    @MainActor
    func failureResultPillHueIsFailure() async {
        let summary = ImportSummary(
            lastResult: .failure(reason: "Network error", at: Date()),
            activeJobCount: 0
        )
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.pillHue == .failure)
    }

    @Test("Failure result pillLabel says failed")
    @MainActor
    func failureResultPillLabel() async {
        let summary = ImportSummary(
            lastResult: .failure(reason: "Timeout", at: Date()),
            activeJobCount: 0
        )
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.pillLabel.lowercased().contains("fail"))
    }

    @Test("hasActiveJob is true when activeJobCount > 0")
    @MainActor
    func hasActiveJobTrueWhenPositiveCount() async {
        let summary = ImportSummary(lastResult: .none, activeJobCount: 2)
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.hasActiveJob)
    }

    @Test("hasActiveJob is false when activeJobCount is 0")
    @MainActor
    func hasActiveJobFalseWhenZeroCount() async {
        let summary = ImportSummary(lastResult: .none, activeJobCount: 0)
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(!vm.hasActiveJob)
    }

    @Test("lastResultDate is nil for .none result")
    @MainActor
    func lastResultDateNilForNone() async {
        let summary = ImportSummary(lastResult: .none)
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.lastResultDate == nil)
    }

    @Test("lastResultDate is populated for success result")
    @MainActor
    func lastResultDatePopulatedForSuccess() async {
        let date = Date(timeIntervalSinceNow: -3600)
        let summary = ImportSummary(lastResult: .success(entityCount: 1, at: date))
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.lastResultDate == date)
    }

    @Test("lastResultDate is populated for failure result")
    @MainActor
    func lastResultDatePopulatedForFailure() async {
        let date = Date(timeIntervalSinceNow: -7200)
        let summary = ImportSummary(lastResult: .failure(reason: "err", at: date))
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.lastResultDate == date)
    }

    @Test("None result pillLabel says no imports yet")
    @MainActor
    func noneResultPillLabel() async {
        let summary = ImportSummary(lastResult: .none)
        let vm = ImportStatusSummaryViewModel(provider: StubImportProvider(summary))
        await vm.load()
        #expect(vm.pillLabel.lowercased().contains("no"))
    }
}

// MARK: - ExportStatusSummaryViewModel Tests

@Suite("ExportStatusSummaryViewModel")
struct ExportStatusSummaryViewModelTests {

    @Test("Initial state is idle")
    @MainActor
    func initialStateIsIdle() {
        let vm = ExportStatusSummaryViewModel(provider: nil)
        guard case .idle = vm.state else {
            Issue.record("Expected .idle, got \(vm.state)")
            return
        }
    }

    @Test("Nil provider transitions to loaded with empty summary")
    @MainActor
    func nilProviderLoadsEmpty() async {
        let vm = ExportStatusSummaryViewModel(provider: nil)
        await vm.load()
        guard case .loaded(let summary) = vm.state else {
            Issue.record("Expected .loaded after nil-provider load")
            return
        }
        #expect(summary == ExportSummary())
    }

    @Test("Nil provider: pillHue is neutral")
    @MainActor
    func nilProviderPillHueIsNeutral() async {
        let vm = ExportStatusSummaryViewModel(provider: nil)
        await vm.load()
        #expect(vm.pillHue == .neutral)
    }

    @Test("Nil provider: isExporting is false")
    @MainActor
    func nilProviderIsNotExporting() async {
        let vm = ExportStatusSummaryViewModel(provider: nil)
        await vm.load()
        #expect(!vm.isExporting)
    }

    @Test("Success result sets pillHue to success")
    @MainActor
    func successResultPillHueIsSuccess() async {
        let summary = ExportSummary(lastResult: .success(at: Date()))
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.pillHue == .success)
    }

    @Test("Success result pillLabel says ready")
    @MainActor
    func successResultPillLabel() async {
        let summary = ExportSummary(lastResult: .success(at: Date()))
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.pillLabel.lowercased().contains("ready"))
    }

    @Test("Failure result sets pillHue to failure")
    @MainActor
    func failureResultPillHueIsFailure() async {
        let summary = ExportSummary(lastResult: .failure(reason: "S3 error", at: Date()))
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.pillHue == .failure)
    }

    @Test("Failure result pillLabel says failed")
    @MainActor
    func failureResultPillLabel() async {
        let summary = ExportSummary(lastResult: .failure(reason: "err", at: Date()))
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.pillLabel.lowercased().contains("fail"))
    }

    @Test("isExporting is true when summary says so")
    @MainActor
    func isExportingTrueFromSummary() async {
        let summary = ExportSummary(lastResult: .none, isExporting: true)
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.isExporting)
    }

    @Test("isExporting is false when summary says false")
    @MainActor
    func isExportingFalseFromSummary() async {
        let summary = ExportSummary(lastResult: .none, isExporting: false)
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(!vm.isExporting)
    }

    @Test("nextRunLabel is nil when nextScheduledRunAt is nil")
    @MainActor
    func nextRunLabelNilWhenNoSchedule() async {
        let summary = ExportSummary(lastResult: .none, nextScheduledRunAt: nil)
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.nextRunLabel == nil)
    }

    @Test("nextRunLabel is non-nil when nextScheduledRunAt is set")
    @MainActor
    func nextRunLabelPresentWhenScheduled() async {
        let iso = "2026-05-01T08:00:00Z"
        let summary = ExportSummary(lastResult: .none, nextScheduledRunAt: iso)
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        let label = vm.nextRunLabel
        #expect(label != nil)
        #expect(label?.lowercased().contains("next") == true)
    }

    @Test("lastResultDate is nil for .none result")
    @MainActor
    func lastResultDateNilForNone() async {
        let summary = ExportSummary(lastResult: .none)
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.lastResultDate == nil)
    }

    @Test("lastResultDate is populated for success result")
    @MainActor
    func lastResultDatePopulatedForSuccess() async {
        let date = Date(timeIntervalSinceNow: -1800)
        let summary = ExportSummary(lastResult: .success(at: date))
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.lastResultDate == date)
    }

    @Test("lastResultDate is populated for failure result")
    @MainActor
    func lastResultDatePopulatedForFailure() async {
        let date = Date(timeIntervalSinceNow: -900)
        let summary = ExportSummary(lastResult: .failure(reason: "err", at: date))
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.lastResultDate == date)
    }

    @Test("None result pillLabel says no exports yet")
    @MainActor
    func noneResultPillLabel() async {
        let summary = ExportSummary(lastResult: .none)
        let vm = ExportStatusSummaryViewModel(provider: StubExportProvider(summary))
        await vm.load()
        #expect(vm.pillLabel.lowercased().contains("no"))
    }
}

// MARK: - DataBridgeDependencies Tests

@Suite("DataBridgeDependencies")
struct DataBridgeDependenciesTests {

    @Test("Default init has nil deepLink")
    func defaultDepsHasNilDeepLink() {
        let deps = DataBridgeDependencies()
        #expect(deps.deepLink == nil)
    }

    @Test("Default init has nil importProvider")
    func defaultDepsHasNilImportProvider() {
        let deps = DataBridgeDependencies()
        #expect(deps.importProvider == nil)
    }

    @Test("Default init has nil exportProvider")
    func defaultDepsHasNilExportProvider() {
        let deps = DataBridgeDependencies()
        #expect(deps.exportProvider == nil)
    }

    @Test("ImportSummary default is equatable to itself")
    func importSummaryDefaultEquality() {
        let a = ImportSummary()
        let b = ImportSummary()
        #expect(a == b)
    }

    @Test("ExportSummary default is equatable to itself")
    func exportSummaryDefaultEquality() {
        let a = ExportSummary()
        let b = ExportSummary()
        #expect(a == b)
    }

    @Test("ImportSummary with success differs from none")
    func importSummarySuccessDiffersFromNone() {
        let none = ImportSummary(lastResult: .none)
        let success = ImportSummary(lastResult: .success(entityCount: 1, at: Date()))
        #expect(none != success)
    }

    @Test("ExportSummary with failure differs from none")
    func exportSummaryFailureDiffersFromNone() {
        let none = ExportSummary(lastResult: .none)
        let failure = ExportSummary(lastResult: .failure(reason: "x", at: Date()))
        #expect(none != failure)
    }
}
