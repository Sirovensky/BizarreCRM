#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - NoPrinterFallbackView
//
// §17.4 "No printer configured — offer email / SMS with PDF attachment + in-app preview"
//
// Presented as a sheet when a print action fires but no printer is paired.
// The PDF is rendered on-device from the local ReceiptPayload — never a remote URL.
// Works fully offline (delivery may queue if cellular/Wi-Fi is unavailable, but
// the PDF is ready immediately).

/// Sheet shown when no printer is configured.
///
/// Provides three paths:
/// 1. **In-app preview** — scrollable view of the rendered receipt.
/// 2. **Share** — `UIActivityViewController` with the local PDF attached.
/// 3. **Settings** — caller-supplied callback to navigate to printer settings.
public struct NoPrinterFallbackView: View {

    // MARK: - Input

    /// The receipt payload to render for preview / sharing.
    public let payload: ReceiptPayload
    public let medium: PrintMedium
    public let onAddPrinter: () -> Void
    public let onDismiss: () -> Void

    // MARK: - State

    @State private var showPreview: Bool = false
    @State private var shareURL: URL?
    @State private var isRenderingPDF: Bool = false
    @State private var pdfError: String?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    public init(
        payload: ReceiptPayload,
        medium: PrintMedium = .thermal80mm,
        onAddPrinter: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.payload = payload
        self.medium = medium
        self.onAddPrinter = onAddPrinter
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Illustration header
                VStack(spacing: 12) {
                    Image(systemName: "printer.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No Printer Configured")
                        .font(.headline)
                    Text("Add a receipt printer in Settings, or share / preview the receipt now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(24)

                Divider()

                // Action list
                List {
                    Section("Receipt Options") {
                        Button {
                            showPreview = true
                        } label: {
                            Label("View Receipt", systemImage: "doc.text.magnifyingglass")
                        }
                        .accessibilityLabel("View receipt in app")

                        spinningButton(title: "Share / Email PDF",
                                       systemImage: "square.and.arrow.up",
                                       running: isRenderingPDF) {
                            await shareAsPDF()
                        }
                    }

                    Section("Setup") {
                        Button {
                            onAddPrinter()
                            dismiss()
                        } label: {
                            Label("Add a Printer", systemImage: "printer.badge.plus")
                        }
                        .accessibilityLabel("Open printer settings to add a printer")
                    }
                }
                .listStyle(.insetGrouped)

                if let err = pdfError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.bizarreError)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .accessibilityLabel("Error: \(err)")
                }
            }
            .navigationTitle("Print Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showPreview) {
            receiptPreviewSheet
        }
        .sheet(item: $shareURL) { url in
            ShareSheetWrapper(url: url)
        }
    }

    // MARK: - In-app preview sheet

    private var receiptPreviewSheet: some View {
        NavigationStack {
            ScrollView {
                ReceiptView(model: payload)
                    .environment(\.printMedium, medium)
                    .padding()
            }
            .navigationTitle("Receipt Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showPreview = false }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    spinningButton(title: "Share", systemImage: "square.and.arrow.up",
                                   running: isRenderingPDF) {
                        await shareAsPDF()
                        showPreview = false
                    }
                }
            }
        }
    }

    // MARK: - PDF generation + share

    @MainActor
    private func shareAsPDF() async {
        isRenderingPDF = true
        pdfError = nil
        defer { isRenderingPDF = false }
        do {
            let view = ReceiptView(model: payload).environment(\.printMedium, medium)
            let url = try await ReceiptRenderer.renderPDF(view, medium: medium)
            shareURL = url
        } catch {
            pdfError = "Could not generate PDF: \(error.localizedDescription)"
            AppLog.hardware.error("NoPrinterFallbackView: PDF generation failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Async button helper

    @ViewBuilder
    private func spinningButton(
        title: String,
        systemImage: String,
        running: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            guard !running else { return }
            Task { await action() }
        } label: {
            Label {
                HStack {
                    Text(title)
                    if running { ProgressView().scaleEffect(0.8) }
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .disabled(running)
    }
}

// MARK: - ShareSheetWrapper

/// Presents `UIActivityViewController` from a SwiftUI `.sheet`.
private struct ShareSheetWrapper: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - URL: Identifiable (for .sheet(item:))

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#endif
