#if canImport(UIKit)
import Foundation
import UIKit
import Core

// MARK: - PrintService
//
// §17 high-level print orchestrator:
//   - Owns the PrintJobQueue (per-session) and routes jobs to the active printer.
//   - Exposes a published toast message ("Print queued, 1 pending" / "Printing…").
//   - Presents a first-page preview before sending to any physical printer.
//   - Falls back to PDF share sheet when no printer is configured.
//   - Works offline: thermal/BT printers on the local network have no internet
//     dependency; the queue drains when the printer becomes reachable.
//
// Thread safety: @Observable + @MainActor for UI-facing properties.
//               actor-isolated PrintJobQueue for queue mutations.

@Observable
@MainActor
public final class PrintService {

    // MARK: - Public state (drives UI)

    /// Current toast message; nil when nothing to show.
    public private(set) var toastMessage: String?

    /// Count of jobs waiting in the queue.
    public var pendingCount: Int = 0

    /// True while a print job is being sent.
    public private(set) var isPrinting: Bool = false

    // MARK: - Dependencies

    private let queue: PrintJobQueue
    private let settings: PrinterProfileStore

    // MARK: - Init

    /// - Parameters:
    ///   - engine: The `PrintEngine` to use for sending jobs.
    ///   - settings: Store that provides the active printer profile.
    ///   - queuePolicy: Retry / backoff policy for the job queue.
    public init(
        engine: any PrintEngine,
        settings: PrinterProfileStore,
        queuePolicy: PrintJobQueue.Policy = .default
    ) {
        self.queue = PrintJobQueue(engine: engine, policy: queuePolicy)
        self.settings = settings
    }

    // MARK: - Print (with preview gate)

    /// Submit a print job.
    ///
    /// - Parameters:
    ///   - job: The job to print.
    ///   - previewImage: Optional first-page preview rendered by the caller.
    ///     Pass a non-nil image to show a preview before printing.
    ///   - presenter: The `UIViewController` to present the preview from.
    ///     Required only when `previewImage` is non-nil.
    /// - Returns: `true` if the job was queued (user confirmed); `false` if cancelled.
    @discardableResult
    public func submit(
        _ job: PrintJob,
        previewImage: UIImage? = nil,
        presenter: UIViewController? = nil
    ) async -> Bool {
        // If a preview image was provided, show it and wait for user confirmation.
        if let preview = previewImage, let vc = presenter {
            let confirmed = await showPreview(preview, in: vc)
            guard confirmed else {
                showToast("Print cancelled.")
                return false
            }
        }

        guard let printer = settings.activeReceiptPrinter else {
            // No printer configured → fall back to PDF share sheet.
            await fallbackToShareSheet(job, from: presenter)
            return true
        }

        await enqueue(job, to: printer)
        return true
    }

    // MARK: - PDF share-sheet fallback

    /// Present a `UIActivityViewController` sharing the job payload as a PDF.
    /// Used when no printer is configured.
    public func fallbackToShareSheet(_ job: PrintJob, from presenter: UIViewController?) async {
        guard let vc = presenter else {
            showToast("No printer configured.")
            return
        }
        showToast("No printer configured — share PDF instead.")
        let pdfData = makeFallbackPDFData(for: job)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("print-\(job.id.uuidString)-fallback.pdf")
        do {
            try pdfData.write(to: tempURL)
        } catch {
            showToast("Could not create PDF: \(error.localizedDescription)")
            return
        }
        let activity = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        // iPad popover anchor: centre of the view.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = vc.view
            popover.sourceRect = CGRect(
                x: vc.view.bounds.midX,
                y: vc.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            activity.completionWithItemsHandler = { _, _, _, _ in continuation.resume() }
            vc.present(activity, animated: true)
        }
    }

    // MARK: - Submit with options (§17 reprint cluster)

    /// Submit a print job using the result of `PrintOptionsSheet`.
    ///
    /// This is the preferred entry point for all reprint flows because it
    /// handles all §17 reprint requirements in one call:
    ///   - Printer choice: uses `options.selectedPrinter` or falls back to
    ///     `settings.activeReceiptPrinter`.
    ///   - Paper size: applies `options.paperSize` to the job's render path
    ///     (stored in `PrintOptions`; consumers pass it to the renderer before
    ///     calling this method).
    ///   - Copies: `options.copies` is forwarded to `PrintJob.copies` so the
    ///     queue sends N physical prints.
    ///   - Reprint audit: when `entityKind` + `entityId` + an `APIClient`-
    ///     conforming `auditLogger` are supplied and `options.reason` is present,
    ///     a `document_reprint` audit event is POSTed to the server.
    ///   - Fallback: no printer configured → PDF share sheet (same as `submit`).
    ///
    /// - Parameters:
    ///   - job: The `PrintJob` to send. `copies` on the job is overridden by
    ///     `options.copies`; all other job fields are used as-is.
    ///   - options: The result from `PrintOptionsSheet.onConfirm`.
    ///   - auditLogger: Optional closure that fires the server audit call.
    ///     Signature: `(entityKind, entityId, reasonString, documentType) async throws`.
    ///     Pass `nil` to skip audit (e.g. first-print, not a reprint).
    ///   - entityKind: e.g. `"sale"`, `"invoice"`, `"ticket"`. Used in audit.
    ///   - entityId: Numeric entity ID. Used in audit.
    ///   - presenter: The `UIViewController` to present preview / share sheet from.
    /// - Returns: `true` if printed or handed to share sheet; `false` if cancelled.
    @discardableResult
    public func submitWithOptions(
        _ job: PrintJob,
        options: PrintOptions,
        auditLogger: (@Sendable (String, Int64, String?, String) async throws -> Void)? = nil,
        entityKind: String = "sale",
        entityId: Int64 = 0,
        presenter: UIViewController? = nil
    ) async -> Bool {
        // 1. Build a copies-aware version of the job.
        let jobWithCopies = PrintJob(
            id: job.id,
            kind: job.kind,
            payload: job.payload,
            createdAt: job.createdAt,
            kickDrawer: job.kickDrawer,
            copies: options.copies
        )

        // 2. Resolve printer: prefer the one selected in the sheet.
        let resolvedPrinter = options.selectedPrinter ?? settings.activeReceiptPrinter

        // 3. Fire reprint audit if a logger and entity context were provided.
        if let logger = auditLogger, entityId > 0 {
            let reasonString = options.reason?.rawValue
            let docType = job.payload.documentType.displayName
            do {
                try await logger(entityKind, entityId, reasonString, docType)
            } catch {
                // Audit failure is non-fatal — log and proceed.
                AppLog.hardware.warning("PrintService: reprint audit failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 4. No printer → fallback to PDF share sheet.
        guard let printer = resolvedPrinter else {
            await fallbackToShareSheet(jobWithCopies, from: presenter)
            return true
        }

        // 5. Submit to queue (no preview gate for reprints — user already saw the doc).
        await enqueue(jobWithCopies, to: printer)
        return true
    }

    // MARK: - Reprint entry (from queue or history)

    /// Re-queue a job by its ID from the dead-letter queue.
    /// If not found in dead-letter, logs a warning and does nothing.
    public func retryDeadLetter(id: UUID, to printer: Printer? = nil) async {
        let targetPrinter = printer ?? settings.activeReceiptPrinter
        guard let targetPrinter else {
            showToast("No printer configured for retry.")
            return
        }
        await queue.retryDeadLetter(id: id, to: targetPrinter)
        await refreshPendingCount()
    }

    // MARK: - Manual drain

    /// Re-attempt all queued jobs immediately (e.g. on reconnect).
    public func drainQueue() async {
        guard pendingCount > 0 else { return }
        showToast("Retrying \(pendingCount) queued print job(s)…")
        await queue.drain()
        await refreshPendingCount()
    }

    // MARK: - Private helpers

    private func enqueue(_ job: PrintJob, to printer: Printer) async {
        isPrinting = true
        await queue.enqueue(job, to: printer)
        isPrinting = false
        await refreshPendingCount()
        if pendingCount > 0 {
            showToast("Print queued — \(pendingCount) pending")
        } else {
            showToast("Printed.")
        }
        AppLog.hardware.info("PrintService: submitted job \(job.id, privacy: .public) kind=\(job.kind.rawValue, privacy: .public)")
    }

    private func refreshPendingCount() async {
        pendingCount = await queue.pendingCount
    }

    private func showToast(_ message: String) {
        toastMessage = message
        // Auto-clear after 3 s.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    /// Present a full-screen preview sheet and wait for the user to confirm or cancel.
    @MainActor
    private func showPreview(_ image: UIImage, in vc: UIViewController) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let previewVC = PrintPreviewViewController(image: image) { confirmed in
                continuation.resume(returning: confirmed)
            }
            vc.present(previewVC, animated: true)
        }
    }

    /// Create a minimal PDF from a print job (fallback path when no printer configured).
    private func makeFallbackPDFData(for job: PrintJob) -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792)
        )
        return renderer.pdfData { context in
            context.beginPage()
            let text: NSString
            switch job.payload {
            case .receipt(let p):
                text = "\(p.tenantName)\n\(p.receiptNumber)\nTotal: \(p.totalCents)" as NSString
            case .label(let p):
                text = "\(p.customerName)\nTicket: \(p.ticketNumber)" as NSString
            case .ticketTag(let p):
                text = "\(p.customerName)\n\(p.ticketNumber)" as NSString
            case .barcode(let p):
                text = "\(p.code) [\(p.format.rawValue)]" as NSString
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ]
            text.draw(in: CGRect(x: 36, y: 36, width: 540, height: 720), withAttributes: attrs)
        }
    }
}

// MARK: - PrintPreviewViewController

/// Modal that shows a first-page render of the document.
/// User taps "Print" to confirm or "Cancel" to abort.
@MainActor
final class PrintPreviewViewController: UIViewController {

    private let image: UIImage
    private let completion: (Bool) -> Void

    init(image: UIImage, completion: @escaping (Bool) -> Void) {
        self.image = image
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.accessibilityLabel = "Print preview — first page"
        view.addSubview(imageView)

        let printButton = UIButton(type: .system)
        printButton.setTitle("Print", for: .normal)
        printButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        printButton.translatesAutoresizingMaskIntoConstraints = false
        printButton.accessibilityLabel = "Confirm print"
        printButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        view.addSubview(printButton)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.secondaryLabel, for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.accessibilityLabel = "Cancel print"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            imageView.bottomAnchor.constraint(equalTo: printButton.topAnchor, constant: -16),

            printButton.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -8),
            printButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            printButton.heightAnchor.constraint(equalToConstant: 44),
            printButton.widthAnchor.constraint(equalToConstant: 200),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func confirmTapped() {
        dismiss(animated: true) { self.completion(true) }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { self.completion(false) }
    }
}

#endif
