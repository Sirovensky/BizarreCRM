#if canImport(UIKit)
import Foundation
import CoreImage
import UIKit
import Core

// MARK: - BulkRelabelService
//
// §17.2 — "Tenant bulk relabel: Inventory 'Regenerate barcodes' for all SKUs →
//           print via §17."
//
// Flow:
//   1. Caller provides a list of `InventoryRelabelItem` (SKU, name, barcode string).
//   2. For each item, a `PrintJob(kind: .barcode, payload: .barcode(…))` is
//      submitted to `PrintService` — routing follows the same §17.4 pipeline:
//        - Thermal label/receipt printer: rasterized ESC/POS
//        - AirPrint: PDF label sheet
//        - No printer: PDF share sheet
//   3. Progress is published via `BulkRelabelProgress` so `BulkRelabelView` can
//      render a progress bar and per-item status.
//
// Rate limiting: label jobs are dispatched one per 200 ms to avoid overwhelming
// a slow BT printer. The caller can cancel via the returned `Task`.

// MARK: - InventoryRelabelItem

/// One inventory item to be relabelled.
public struct InventoryRelabelItem: Sendable, Identifiable {
    public let id: String
    public let sku: String
    public let name: String
    /// Barcode string encoded into Code 128 (typically the SKU or tenant-generated EAN-13).
    public let barcodeValue: String
    /// Price in cents, shown on the label.
    public let priceCents: Int?

    public init(id: String, sku: String, name: String, barcodeValue: String, priceCents: Int? = nil) {
        self.id = id
        self.sku = sku
        self.name = name
        self.barcodeValue = barcodeValue
        self.priceCents = priceCents
    }
}

// MARK: - BulkRelabelProgress

/// Observable progress state for a bulk relabel run.
@Observable
public final class BulkRelabelProgress: @unchecked Sendable {
    public var total: Int = 0
    public var completed: Int = 0
    public var failed: Int = 0
    public var currentItem: String = ""
    public var isCancelled: Bool = false

    public var fractionCompleted: Double {
        total == 0 ? 0 : Double(completed + failed) / Double(total)
    }
    public var isFinished: Bool { completed + failed >= total && total > 0 }

    public init() {}
}

// MARK: - BulkRelabelService

public actor BulkRelabelService {

    // MARK: - Singleton

    public static let shared = BulkRelabelService()

    // MARK: - Constants

    /// Inter-job delay to avoid overwhelming slow BT printers.
    private static let labelDelayNanoseconds: UInt64 = 200_000_000 // 200 ms

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Generates a Code 128 barcode print job for each item and submits them to
    /// `printService` with the configured inter-job delay.
    ///
    /// - Parameters:
    ///   - items:        Inventory items to relabel.
    ///   - printService: Wired `PrintService` (resolved from DI container at callsite).
    ///   - progress:     Observable progress holder updated during the run.
    /// - Returns: A cancellable `Task` that the caller can cancel to stop mid-batch.
    @discardableResult
    public func relabel(
        items: [InventoryRelabelItem],
        printService: PrintService,
        progress: BulkRelabelProgress
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                progress.total = items.count
                progress.completed = 0
                progress.failed = 0
                progress.isCancelled = false
            }

            for item in items {
                if Task.isCancelled {
                    await MainActor.run { progress.isCancelled = true }
                    break
                }

                await MainActor.run { progress.currentItem = item.name }

                do {
                    let job = try await self.makeLabelJob(for: item)
                    await MainActor.run {
                        Task { @MainActor in
                            _ = await printService.submit(job)
                        }
                    }
                    await MainActor.run { progress.completed += 1 }
                    AppLog.hardware.info("BulkRelabelService: queued label for SKU '\(item.sku)'")
                } catch {
                    await MainActor.run { progress.failed += 1 }
                    AppLog.hardware.error("BulkRelabelService: failed for SKU '\(item.sku)' — \(error.localizedDescription)")
                }

                try? await Task.sleep(nanoseconds: Self.labelDelayNanoseconds)
            }
        }
    }

    // MARK: - Label job construction

    /// Builds a `PrintJob` for a single inventory item using `BarcodePayload` (Code 128).
    private func makeLabelJob(for item: InventoryRelabelItem) async throws -> PrintJob {
        // Validate barcode value is ASCII-encodable (Code 128 requirement).
        guard item.barcodeValue.data(using: .ascii) != nil else {
            throw BulkRelabelError.invalidBarcodeValue(item.barcodeValue)
        }
        let payload = BarcodePayload(code: item.barcodeValue, format: .code128)
        return PrintJob(kind: .barcode, payload: .barcode(payload), copies: 1)
    }

    // MARK: - Standalone barcode generation

    /// Generates a Code 128 barcode `UIImage` for `value` using Core Image.
    ///
    /// Used when the caller needs the image directly (e.g. for on-screen preview
    /// or sharing without a physical printer).
    ///
    /// Code 128 is the primary symbology for inventory SKU labels per §17.2.
    /// On-device generation; no network call (sovereignty §28).
    public func generateCode128Image(for value: String) throws -> UIImage {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else {
            throw BulkRelabelError.barcodeGenerationFailed("CICode128BarcodeGenerator unavailable")
        }
        guard let data = value.data(using: .ascii) else {
            throw BulkRelabelError.barcodeGenerationFailed("Cannot encode as ASCII: \(value)")
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(7.0, forKey: "inputQuietSpace")

        guard let ciImage = filter.outputImage else {
            throw BulkRelabelError.barcodeGenerationFailed("CIFilter produced nil output")
        }

        // Scale to a useful label size (≈200pt wide).
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 3.0, y: 3.0))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw BulkRelabelError.barcodeGenerationFailed("CGImage creation failed")
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - BulkRelabelError

public enum BulkRelabelError: LocalizedError, Sendable {
    case barcodeGenerationFailed(String)
    case invalidBarcodeValue(String)

    public var errorDescription: String? {
        switch self {
        case .barcodeGenerationFailed(let d):
            return "Barcode generation failed: \(d)"
        case .invalidBarcodeValue(let v):
            return "'\(v)' cannot be encoded as a Code 128 barcode (non-ASCII characters)."
        }
    }
}
#endif
