import Testing
import Foundation
@testable import DataExport

// MARK: - ExportContextMenuActionsTests

@Suite("ExportContextMenuActions — callback bundle")
struct ExportContextMenuActionsTests {

    // MARK: - Callback invocation

    @Test("onDownload callback is invoked when called")
    func downloadCallbackInvoked() {
        var didDownload = false
        let actions = ExportContextMenuActions(
            onDownload: { didDownload = true },
            onCancel: {},
            onViewDetails: {}
        )
        actions.onDownload()
        #expect(didDownload)
    }

    @Test("onCancel callback is invoked when called")
    func cancelCallbackInvoked() {
        var didCancel = false
        let actions = ExportContextMenuActions(
            onDownload: {},
            onCancel: { didCancel = true },
            onViewDetails: {}
        )
        actions.onCancel()
        #expect(didCancel)
    }

    @Test("onViewDetails callback is invoked when called")
    func viewDetailsCallbackInvoked() {
        var didViewDetails = false
        let actions = ExportContextMenuActions(
            onDownload: {},
            onCancel: {},
            onViewDetails: { didViewDetails = true }
        )
        actions.onViewDetails()
        #expect(didViewDetails)
    }

    @Test("onPauseResume is nil when not provided")
    func pauseResumeNilByDefault() {
        let actions = ExportContextMenuActions(
            onDownload: {},
            onCancel: {},
            onViewDetails: {}
        )
        #expect(actions.onPauseResume == nil)
    }

    @Test("onPauseResume is invoked with current paused state")
    func pauseResumeCallbackInvoked() {
        var receivedState: Bool? = nil
        let actions = ExportContextMenuActions(
            onDownload: {},
            onCancel: {},
            onPauseResume: { isPaused in receivedState = isPaused },
            onViewDetails: {}
        )
        actions.onPauseResume?(true)
        #expect(receivedState == true)
        actions.onPauseResume?(false)
        #expect(receivedState == false)
    }

    // MARK: - Multiple callbacks independent

    @Test("Callbacks are independent — one fires without affecting others")
    func callbacksAreIndependent() {
        var downloadCount = 0
        var cancelCount = 0
        let actions = ExportContextMenuActions(
            onDownload: { downloadCount += 1 },
            onCancel: { cancelCount += 1 },
            onViewDetails: {}
        )
        actions.onDownload()
        actions.onDownload()
        actions.onCancel()
        #expect(downloadCount == 2)
        #expect(cancelCount == 1)
    }
}

// MARK: - ExportContextMenuPreviewTests

@Suite("ExportContextMenuPreview — display logic")
struct ExportContextMenuPreviewTests {

    // MARK: - Job status display

    @Test("Completed job has progress 1.0")
    func completedJobProgress() {
        let job = TenantExportJob(id: 1, status: .completed, byteSize: 1024)
        #expect(job.status.progress == 1.0)
    }

    @Test("Failed job has progress 0.0")
    func failedJobProgress() {
        let job = TenantExportJob(id: 2, status: .failed)
        #expect(job.status.progress == 0.0)
    }

    @Test("Exporting job has intermediate progress")
    func exportingJobProgress() {
        let job = TenantExportJob(id: 3, status: .exporting)
        #expect(job.status.progress > 0 && job.status.progress < 1)
    }

    @Test("TenantExportJob with byteSize exposes it correctly")
    func jobByteSizeExposed() {
        let job = TenantExportJob(id: 4, status: .completed, byteSize: 204800)
        #expect(job.byteSize == 204800)
    }

    @Test("TenantExportJob with nil byteSize returns nil")
    func jobByteSizeNil() {
        let job = TenantExportJob(id: 5, status: .queued)
        #expect(job.byteSize == nil)
    }

    // MARK: - Terminal status detection

    @Test("Completed status isTerminal")
    func completedIsTerminal() {
        let job = TenantExportJob(id: 6, status: .completed)
        #expect(job.status.isTerminal)
    }

    @Test("Failed status isTerminal")
    func failedIsTerminal() {
        let job = TenantExportJob(id: 7, status: .failed)
        #expect(job.status.isTerminal)
    }

    @Test("Queued status is not terminal")
    func queuedNotTerminal() {
        let job = TenantExportJob(id: 8, status: .queued)
        #expect(!job.status.isTerminal)
    }

    @Test("Exporting status is not terminal")
    func exportingNotTerminal() {
        let job = TenantExportJob(id: 9, status: .exporting)
        #expect(!job.status.isTerminal)
    }

    // MARK: - Download URL presence (drives "Download" menu visibility)

    @Test("Job with downloadUrl has non-nil URL")
    func jobDownloadUrlPresent() {
        let job = TenantExportJob(id: 10, status: .completed, downloadUrl: "/api/v1/tenant/export/download/abc")
        #expect(job.downloadUrl != nil)
    }

    @Test("Job without downloadUrl is nil")
    func jobDownloadUrlAbsent() {
        let job = TenantExportJob(id: 11, status: .queued)
        #expect(job.downloadUrl == nil)
    }

    @Test("Download action should only be visible for completed jobs with URL")
    func downloadVisibilityLogic() {
        let completedWithUrl = TenantExportJob(id: 12, status: .completed, downloadUrl: "https://example.com")
        let completedNoUrl = TenantExportJob(id: 13, status: .completed, downloadUrl: nil)
        let inProgressWithUrl = TenantExportJob(id: 14, status: .exporting, downloadUrl: "https://example.com")

        // Download should appear only when: completed AND downloadUrl != nil
        let showForCompleted = completedWithUrl.status == .completed && completedWithUrl.downloadUrl != nil
        let showForNoUrl = completedNoUrl.status == .completed && completedNoUrl.downloadUrl != nil
        let showForInProgress = inProgressWithUrl.status == .completed && inProgressWithUrl.downloadUrl != nil

        #expect(showForCompleted == true)
        #expect(showForNoUrl == false)
        #expect(showForInProgress == false)
    }

    @Test("Cancel action should only be visible for non-terminal jobs")
    func cancelVisibilityLogic() {
        let completedJob = TenantExportJob(id: 15, status: .completed)
        let failedJob = TenantExportJob(id: 16, status: .failed)
        let exportingJob = TenantExportJob(id: 17, status: .exporting)
        let queuedJob = TenantExportJob(id: 18, status: .queued)

        #expect(!completedJob.status.isTerminal == false)  // completed is terminal, no cancel
        #expect(!failedJob.status.isTerminal == false)     // failed is terminal, no cancel
        #expect(!exportingJob.status.isTerminal == true)   // not terminal, show cancel
        #expect(!queuedJob.status.isTerminal == true)      // not terminal, show cancel
    }
}
