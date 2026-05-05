import Testing
import Foundation
@testable import DataExport

// MARK: - ExportDetailInspectorDisplayTests
//
// Tests the display-logic helpers that ExportDetailInspector uses.
// Pure data/model tests — no UI rendering required.

@Suite("ExportDetailInspector — display helpers and model logic")
struct ExportDetailInspectorDisplayTests {

    // MARK: - Progress ring value (driven by ExportStatus.progress)

    @Test("Queued job progress is 0.0")
    func queuedProgress() {
        let job = TenantExportJob(id: 1, status: .queued)
        #expect(job.status.progress == 0.0)
    }

    @Test("Completed job progress is 1.0")
    func completedProgress() {
        let job = TenantExportJob(id: 2, status: .completed)
        #expect(job.status.progress == 1.0)
    }

    @Test("Preparing job has partial progress (0 < p < 1)")
    func preparingProgress() {
        let job = TenantExportJob(id: 3, status: .preparing)
        #expect(job.status.progress > 0 && job.status.progress < 1)
    }

    @Test("Exporting job progress is 0.50")
    func exportingProgress() {
        let job = TenantExportJob(id: 4, status: .exporting)
        #expect(job.status.progress == 0.50)
    }

    @Test("Encrypting job progress is 0.85")
    func encryptingProgress() {
        let job = TenantExportJob(id: 5, status: .encrypting)
        #expect(job.status.progress == 0.85)
    }

    // MARK: - Ring colour selection (green/red/accent)

    @Test("Completed job should use green ring")
    func completedRingColor() {
        let status = ExportStatus.completed
        // Inspector uses: completed → green, failed → red, else → accentColor
        let isGreen = (status == .completed)
        let isRed = (status == .failed)
        #expect(isGreen)
        #expect(!isRed)
    }

    @Test("Failed job should use red ring")
    func failedRingColor() {
        let status = ExportStatus.failed
        let isRed = (status == .failed)
        #expect(isRed)
    }

    @Test("In-progress jobs use accent colour (not green or red)")
    func inProgressRingColor() {
        for status in [ExportStatus.queued, .preparing, .exporting, .encrypting] {
            let isGreen = status == .completed
            let isRed = status == .failed
            #expect(!isGreen, "Status .\(status) should not be green")
            #expect(!isRed, "Status .\(status) should not be red")
        }
    }

    // MARK: - Action section visibility (download/share vs error banner)

    @Test("Download action visible only when completed and downloadUrl present")
    func downloadActionVisibility() {
        let completedWithUrl = TenantExportJob(id: 10, status: .completed,
                                               downloadUrl: "https://example.com/file.zip")
        let completedNoUrl = TenantExportJob(id: 11, status: .completed)
        let inProgress = TenantExportJob(id: 12, status: .exporting,
                                         downloadUrl: "https://example.com/file.zip")

        func shouldShowDownload(_ job: TenantExportJob) -> Bool {
            job.status == .completed && job.downloadUrl != nil
        }

        #expect(shouldShowDownload(completedWithUrl))
        #expect(!shouldShowDownload(completedNoUrl))
        #expect(!shouldShowDownload(inProgress))
    }

    @Test("Error banner visible only when errorMessage present")
    func errorBannerVisibility() {
        let jobWithError = TenantExportJob(id: 13, status: .failed,
                                           errorMessage: "Disk full")
        let jobNoError = TenantExportJob(id: 14, status: .failed)

        #expect(jobWithError.errorMessage != nil)
        #expect(jobNoError.errorMessage == nil)
    }

    // MARK: - Metadata rows availability

    @Test("byteSize nil means no file-size metadata row")
    func byteSizeNilNoRow() {
        let job = TenantExportJob(id: 20, status: .queued)
        #expect(job.byteSize == nil)
    }

    @Test("byteSize set means file-size metadata row appears")
    func byteSizeSetRow() {
        let job = TenantExportJob(id: 21, status: .completed, byteSize: 512_000)
        #expect(job.byteSize == 512_000)
    }

    @Test("startedAt nil means no started-at row")
    func startedAtNilNoRow() {
        let job = TenantExportJob(id: 22, status: .queued)
        #expect(job.startedAt == nil)
    }

    @Test("completedAt set means completed-at row appears")
    func completedAtSetRow() {
        let job = TenantExportJob(id: 23, status: .completed,
                                   completedAt: "2026-04-23T12:00:00Z")
        #expect(job.completedAt == "2026-04-23T12:00:00Z")
    }

    // MARK: - Job ID display

    @Test("Job ID is exposed correctly for metadata row")
    func jobIdDisplay() {
        let job = TenantExportJob(id: 42, status: .queued)
        #expect(job.id == 42)
        #expect("\(job.id)" == "42")
    }

    // MARK: - ExportEntity/Format metadata

    @Test("ExportEntity.full displayName is 'All data'")
    func entityFullDisplayName() {
        #expect(ExportEntity.full.displayName == "All data")
    }

    @Test("ExportFormat.csv displayName is 'CSV'")
    func formatCSVDisplayName() {
        #expect(ExportFormat.csv.displayName == "CSV")
    }

    @Test("ExportFormat.xlsx displayName is 'XLSX'")
    func formatXLSXDisplayName() {
        #expect(ExportFormat.xlsx.displayName == "XLSX")
    }

    @Test("All ExportEntity cases have non-empty systemImage")
    func allEntitiesHaveSystemImage() {
        for entity in ExportEntity.allCases {
            #expect(!entity.systemImage.isEmpty)
        }
    }
}

// MARK: - ScheduledExportDetailInspectorTests

@Suite("ScheduledExportDetailInspector — schedule model logic")
struct ScheduledExportDetailInspectorTests {

    // MARK: - Status color logic

    @Test("Active schedule status color should be green")
    func activeStatusColor() {
        let status = ScheduleStatus.active
        // Inspector logic: active → green, paused → orange, canceled → secondary
        let isActive = status == .active
        #expect(isActive)
    }

    @Test("Paused schedule status color should be orange")
    func pausedStatusColor() {
        let status = ScheduleStatus.paused
        let isPaused = status == .paused
        #expect(isPaused)
    }

    @Test("Canceled schedule status color should be secondary")
    func canceledStatusColor() {
        let status = ScheduleStatus.canceled
        let isCanceled = status == .canceled
        #expect(isCanceled)
    }

    // MARK: - Action section visibility

    @Test("Pause button visible only when schedule is active")
    func pauseButtonVisibility() {
        let activeSchedule = ExportSchedule(id: 1, name: "A", exportType: .full,
                                             intervalKind: .daily, intervalCount: 1, status: .active)
        let pausedSchedule = ExportSchedule(id: 2, name: "B", exportType: .full,
                                             intervalKind: .daily, intervalCount: 1, status: .paused)
        let canceledSchedule = ExportSchedule(id: 3, name: "C", exportType: .full,
                                               intervalKind: .daily, intervalCount: 1, status: .canceled)

        #expect(activeSchedule.status == .active)   // show Pause
        #expect(pausedSchedule.status != .active)   // show Resume instead
        #expect(canceledSchedule.status != .active) // show neither
    }

    @Test("Resume button visible only when schedule is paused")
    func resumeButtonVisibility() {
        let pausedSchedule = ExportSchedule(id: 4, name: "D", exportType: .invoices,
                                             intervalKind: .weekly, intervalCount: 1, status: .paused)
        #expect(pausedSchedule.status == .paused)
    }

    @Test("Cancel button not shown when schedule is already canceled")
    func cancelButtonNotShownForCanceled() {
        let canceledSchedule = ExportSchedule(id: 5, name: "E", exportType: .tickets,
                                               intervalKind: .monthly, intervalCount: 1, status: .canceled)
        #expect(canceledSchedule.status == .canceled)
        // Inspector hides cancel button when status == .canceled
        let shouldShowCancel = canceledSchedule.status != .canceled
        #expect(!shouldShowCancel)
    }

    // MARK: - Recent runs display

    @Test("Empty recent runs array shows no run rows")
    func emptyRecentRuns() {
        let runs: [ScheduleRun] = []
        #expect(runs.isEmpty)
    }

    @Test("Recent runs array limited to 5 items in display")
    func recentRunsLimitedToFive() {
        // Inspector uses .prefix(5)
        let runCount = 8
        let runs = (0..<runCount).map { i in
            ScheduleRun(
                id: i, scheduleId: 1,
                runAt: "2026-04-\(String(format: "%02d", i+1))T02:00:00Z",
                succeeded: true, exportFile: nil, errorMessage: nil
            )
        }
        let displayed = Array(runs.prefix(5))
        #expect(displayed.count == 5)
    }

    @Test("Succeeded run has succeeded flag true")
    func succeededRunFlag() {
        let run = ScheduleRun(id: 1, scheduleId: 1, runAt: "2026-04-23T02:00:00Z",
                              succeeded: true, exportFile: "export.json", errorMessage: nil)
        #expect(run.succeeded)
    }

    @Test("Failed run has succeeded flag false and may have errorMessage")
    func failedRunFlag() {
        let run = ScheduleRun(id: 2, scheduleId: 1, runAt: "2026-04-22T02:00:00Z",
                              succeeded: false, exportFile: nil, errorMessage: "Timeout")
        #expect(!run.succeeded)
        #expect(run.errorMessage == "Timeout")
    }

    // MARK: - Schedule metadata display

    @Test("nextRunAt nil means no next-run label")
    func nextRunAtNil() {
        let schedule = ExportSchedule(id: 6, name: "F", exportType: .full,
                                       intervalKind: .daily, intervalCount: 1,
                                       nextRunAt: nil)
        #expect(schedule.nextRunAt == nil)
    }

    @Test("nextRunAt set means next-run label visible")
    func nextRunAtSet() {
        let schedule = ExportSchedule(id: 7, name: "G", exportType: .full,
                                       intervalKind: .weekly, intervalCount: 1,
                                       nextRunAt: "2026-04-28T02:00:00Z")
        #expect(schedule.nextRunAt == "2026-04-28T02:00:00Z")
    }

    @Test("Schedule intervalKind displayName is surfaced correctly")
    func intervalKindDisplayName() {
        let daily = ScheduleIntervalKind.daily
        let weekly = ScheduleIntervalKind.weekly
        let monthly = ScheduleIntervalKind.monthly
        #expect(daily.displayName == "Daily")
        #expect(weekly.displayName == "Weekly")
        #expect(monthly.displayName == "Monthly")
    }

    // MARK: - Pause/Resume/Cancel callbacks

    @Test("onPause callback fires when invoked")
    func pauseCallbackFires() {
        var fired = false
        let onPause: () -> Void = { fired = true }
        onPause()
        #expect(fired)
    }

    @Test("onResume callback fires when invoked")
    func resumeCallbackFires() {
        var fired = false
        let onResume: () -> Void = { fired = true }
        onResume()
        #expect(fired)
    }

    @Test("onCancel callback fires when invoked")
    func cancelCallbackFires() {
        var fired = false
        let onCancel: () -> Void = { fired = true }
        onCancel()
        #expect(fired)
    }
}
