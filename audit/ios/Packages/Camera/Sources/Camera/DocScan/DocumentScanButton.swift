#if canImport(UIKit) && canImport(VisionKit)
import SwiftUI
import VisionKit
import Core

// MARK: - DocumentScanButton
//
// §17 entry point: "Entry from customer detail / ticket detail → 'Scan document'"
//
// A button that presents `DocumentScannerView` as a sheet/fullScreenCover.
// Embeds directly in any customer or ticket detail view.
//
// Usage in customer detail:
// ```swift
// DocumentScanButton(entityKind: .customer, entityId: customerId) { result in
//     viewModel.attachDocument(result)
// }
// ```
//
// Usage in ticket detail:
// ```swift
// DocumentScanButton(entityKind: .ticket, entityId: ticketId) { result in
//     viewModel.attachDocument(result)
// }
// ```

public struct DocumentScanButton: View {

    // MARK: - Types

    public enum EntityKind: String, Sendable {
        case customer = "Customer"
        case ticket   = "Ticket"
    }

    // MARK: - State

    @State private var isPresenting = false
    @State private var scanError: String?

    // MARK: - Configuration

    private let entityKind: EntityKind
    private let entityId: String
    private let onFinished: @Sendable (ScanResult) -> Void

    // MARK: - Init

    public init(
        entityKind: EntityKind,
        entityId: String,
        onFinished: @escaping @Sendable (ScanResult) -> Void
    ) {
        self.entityKind = entityKind
        self.entityId = entityId
        self.onFinished = onFinished
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if VNDocumentCameraViewController.isSupported {
                Button(action: { isPresenting = true }) {
                    Label("Scan Document", systemImage: "doc.viewfinder")
                }
                .accessibilityLabel("Scan a document and attach to this \(entityKind.rawValue.lowercased())")
                .accessibilityHint("Opens the document scanner camera.")
            } else {
                // Mac Catalyst or unsupported device — graceful disable
                Button(action: {}) {
                    Label("Scan Document", systemImage: "doc.viewfinder")
                }
                .disabled(true)
                .accessibilityLabel("Document scanning is unavailable on this device")
            }
        }
        .sheet(isPresented: $isPresenting) {
            DocumentScannerView(
                onFinished: { result in
                    isPresenting = false
                    onFinished(result)
                },
                onCanceled: { isPresenting = false },
                onError: { err in
                    isPresenting = false
                    scanError = err.localizedDescription
                }
            )
        }
        .alert("Scan Error", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("OK", role: .cancel) { scanError = nil }
        } message: {
            Text(scanError ?? "")
        }
    }
}

// MARK: - ScanResult (public result type from DocumentScanner)

// ScanResult is already defined in DocumentScanner.swift.
// This file only adds the button entry-point.

#endif
