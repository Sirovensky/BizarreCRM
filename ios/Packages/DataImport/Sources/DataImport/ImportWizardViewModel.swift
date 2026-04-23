import Foundation
import Observation
import Core
import Networking

// MARK: - Wizard step

public enum ImportWizardStep: Equatable, Sendable, CaseIterable {
    case chooseSource
    case chooseEntity
    case upload
    case preview
    case mapping
    case start
    case progress
    case done
    case errors

    public var title: String {
        switch self {
        case .chooseSource: return "Choose Source"
        case .chooseEntity: return "Select Entity"
        case .upload:       return "Upload File"
        case .preview:      return "Preview"
        case .mapping:      return "Map Columns"
        case .start:        return "Confirm"
        case .progress:     return "Importing"
        case .done:         return "Done"
        case .errors:       return "Errors"
        }
    }

    public var systemImage: String {
        switch self {
        case .chooseSource: return "square.grid.2x2"
        case .chooseEntity: return "tray.2"
        case .upload:       return "arrow.up.doc"
        case .preview:      return "eye"
        case .mapping:      return "arrow.left.arrow.right"
        case .start:        return "checkmark.circle"
        case .progress:     return "chart.bar"
        case .done:         return "checkmark.seal"
        case .errors:       return "exclamationmark.triangle"
        }
    }

    /// Steps visible in sidebar / step indicator (excludes transient states).
    public static var wizardSteps: [ImportWizardStep] {
        [.chooseSource, .chooseEntity, .upload, .preview, .mapping, .start, .progress]
    }
}

// MARK: - Wizard view model

@MainActor
@Observable
public final class ImportWizardViewModel {

    // MARK: - State

    public private(set) var currentStep: ImportWizardStep = .chooseSource
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    // Choose source step
    public var selectedSource: ImportSource? = nil

    // Choose entity step
    public var selectedEntity: ImportEntityType = .customers

    // Upload step
    public private(set) var uploadedFileId: String? = nil
    public var selectedFilename: String? = nil
    public var selectedFileSize: Int64 = 0
    public private(set) var uploadProgress: Double = 0
    public internal(set) var jobId: String? = nil

    // Preview step
    public private(set) var preview: ImportPreview? = nil

    // Mapping step
    public var columnMapping: [String: String] = [:] // sourceColumn -> CRMField.rawValue

    // Progress step -- job polling + checkpoint
    public internal(set) var job: ImportJob? = nil
    public private(set) var rowErrors: [ImportRowError] = []
    public internal(set) var checkpoint: ImportCheckpoint? = nil

    // Rollback state
    public private(set) var isRollingBack: Bool = false
    public private(set) var rollbackMessage: String? = nil

    // MARK: - Dependencies

    @ObservationIgnored private let repository: ImportRepository
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(repository: ImportRepository) {
        self.repository = repository
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Step transitions

    /// Move from .chooseSource -> .chooseEntity
    public func confirmSource() {
        guard selectedSource != nil else { return }
        transition(to: .chooseEntity)
    }

    /// Move from .chooseEntity -> .upload
    public func confirmEntity() {
        transition(to: .upload)
    }

    /// Called after user picks a file and upload completes
    public func uploadFile(data: Data, filename: String) async {
        guard let source = selectedSource else { return }
        isLoading = true
        errorMessage = nil
        uploadProgress = 0
        do {
            // Upload file -> fileId
            let uploadResp = try await repository.uploadFile(data: data, filename: filename)
            uploadProgress = 0.5

            // Create import job (entity type now included)
            let jobResp = try await repository.createJob(
                source: source,
                entityType: selectedEntity,
                fileId: uploadResp.fileId,
                mapping: nil
            )
            jobId = jobResp.importId
            uploadedFileId = uploadResp.fileId
            uploadProgress = 1.0

            isLoading = false
            transition(to: .preview)
        } catch {
            isLoading = false
            uploadProgress = 0
            errorMessage = error.localizedDescription
            AppLog.ui.error("Import upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load preview after upload
    public func loadPreview() async {
        guard let id = jobId else { return }
        isLoading = true
        errorMessage = nil
        do {
            let p = try await repository.getPreview(id: id)
            preview = p
            // Auto-map columns scoped to the selected entity type
            columnMapping = ImportColumnMapper.autoMap(sourceColumns: p.columns, entity: selectedEntity)
            isLoading = false
            transition(to: .mapping)
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            AppLog.ui.error("Import preview failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// User finishes mapping, proceed to confirmation
    public func confirmMapping() {
        guard allRequiredMapped else { return }
        transition(to: .start)
    }

    /// Start the import job
    public func startImport() async {
        guard let id = jobId else { return }
        isLoading = true
        errorMessage = nil
        do {
            // Re-create job with finalized mapping
            _ = try await repository.createJob(
                source: selectedSource ?? .csv,
                entityType: selectedEntity,
                fileId: uploadedFileId,
                mapping: columnMapping
            )
            let started = try await repository.startJob(id: id)
            job = started

            // Initialize checkpoint for chunk tracking
            let totalRows = started.totalRows ?? (preview?.totalRows ?? 0)
            checkpoint = ImportCheckpoint(jobId: id, totalRows: totalRows)

            isLoading = false
            transition(to: .progress)
            startPolling()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            AppLog.ui.error("Import start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Roll back a completed import (within 24 h window).
    public func rollback() async {
        guard let id = jobId, job?.canRollback == true else { return }
        isRollingBack = true
        rollbackMessage = nil
        do {
            let resp = try await repository.rollbackJob(id: id)
            rollbackMessage = resp.message
            // Reflect rollback in local job state immutably
            if let j = job {
                job = ImportJob(
                    id: j.id,
                    source: j.source,
                    entityType: j.entityType,
                    fileId: j.fileId,
                    status: .rolledBack,
                    totalRows: j.totalRows,
                    processedRows: j.processedRows,
                    errorCount: j.errorCount,
                    createdAt: j.createdAt,
                    mapping: j.mapping,
                    rollbackAvailableUntil: nil
                )
            }
            isRollingBack = false
        } catch {
            isRollingBack = false
            rollbackMessage = "Rollback failed: \(error.localizedDescription)"
            AppLog.ui.error("Import rollback failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Navigate to errors view
    public func viewErrors() async {
        guard let id = jobId else { return }
        isLoading = true
        do {
            let errs = try await repository.getErrors(id: id)
            rowErrors = errs
            isLoading = false
            transition(to: .errors)
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    /// Back from errors to progress/done
    public func backFromErrors() {
        transition(to: job?.status == .completed ? .done : .progress)
    }

    // MARK: - Computed helpers

    public var allRequiredMapped: Bool {
        ImportColumnMapper.allRequiredMapped(columnMapping, entity: selectedEntity)
    }

    public var missingRequiredFields: [CRMField] {
        ImportColumnMapper.missingRequired(columnMapping, entity: selectedEntity)
    }

    public var progressFraction: Double {
        // Prefer checkpoint-based progress (chunk level) for smoother UI.
        if let cp = checkpoint {
            return cp.progressFraction
        }
        guard let j = job, let total = j.totalRows, total > 0 else { return 0 }
        return Double(j.processedRows) / Double(total)
    }

    public var etaString: String {
        guard let j = job,
              let total = j.totalRows,
              total > 0,
              j.processedRows > 0 else { return "" }
        let elapsed = Date().timeIntervalSince(j.createdAt)
        let rate = Double(j.processedRows) / elapsed
        guard rate > 0 else { return "" }
        let remaining = Double(total - j.processedRows) / rate
        if remaining < 60 { return "< 1 min" }
        let mins = Int(remaining / 60)
        return "~\(mins) min"
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                guard !Task.isCancelled else { break }
                await self?.pollStatus()
            }
        }
    }

    private func pollStatus() async {
        guard let id = jobId else { return }
        do {
            let updated = try await repository.getJob(id: id)
            job = updated

            // Advance checkpoint to match processed rows
            if var cp = checkpoint {
                let completedChunks = Int(ceil(Double(updated.processedRows) / Double(cp.chunkSize)))
                if completedChunks > cp.nextChunkIndex {
                    cp.nextChunkIndex = completedChunks
                    cp.lastUpdated = Date()
                    checkpoint = cp
                }
            }

            if updated.status == .completed || updated.status == .failed {
                pollTask?.cancel()
                transition(to: updated.status == .completed ? .done : .progress)
            }
        } catch {
            AppLog.ui.error("Import poll failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internal helpers

    private func transition(to step: ImportWizardStep) {
        currentStep = step
        errorMessage = nil
    }

    /// Reset to initial state (for dismiss/cancel).
    public func reset() {
        pollTask?.cancel()
        currentStep = .chooseSource
        selectedSource = nil
        selectedEntity = .customers
        uploadedFileId = nil
        selectedFilename = nil
        selectedFileSize = 0
        uploadProgress = 0
        jobId = nil
        preview = nil
        columnMapping = [:]
        job = nil
        rowErrors = []
        checkpoint = nil
        isLoading = false
        errorMessage = nil
        isRollingBack = false
        rollbackMessage = nil
    }
}
