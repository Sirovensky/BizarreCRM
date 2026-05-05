import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateContextMenu
//
// §22 context-menu content for an Estimate row on iPad.
// Actions:
//   • Open          — selects the estimate in the split view
//   • Send for Signature — presents EstimateSignSheet (uses existing sign VM)
//   • Convert to Ticket  — presents EstimateConvertSheet (uses existing convert VM)
//   • Duplicate     — disabled (no server endpoint exists yet; placeholder)
//   • Archive       — disabled (no server endpoint exists yet; placeholder)
//
// Rendered via .contextMenu { EstimateContextMenu(...) } — this is a
// ViewBuilder, not a standalone View, so it returns opaque content.

#if canImport(UIKit)

public struct EstimateContextMenu: View {

    private let estimate: Estimate
    private let api: APIClient
    private let onTicketCreated: @MainActor (Int64) -> Void

    @State private var showSignSheet = false
    @State private var showConvertSheet = false

    public init(
        estimate: Estimate,
        api: APIClient,
        onTicketCreated: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        self.estimate = estimate
        self.api = api
        self.onTicketCreated = onTicketCreated
    }

    public var body: some View {
        // Open
        Button {
            // Selection is handled by the parent List binding; this action is a
            // semantic hint for VoiceOver / pointer menus.
        } label: {
            Label("Open", systemImage: "doc.text.magnifyingglass")
        }
        .accessibilityLabel("Open estimate \(estimate.orderId ?? "")")

        Divider()

        // Send for Signature
        let isSigned = estimate.status?.lowercased() == "signed"
        Button {
            showSignSheet = true
        } label: {
            Label(
                isSigned ? "Already Signed" : "Send for Signature",
                systemImage: isSigned ? "checkmark.seal.fill" : "pencil.and.signature"
            )
        }
        .disabled(isSigned)
        .accessibilityLabel(isSigned ? "Estimate already signed" : "Send estimate for customer signature")

        // Convert to Ticket
        let isConverted = estimate.status?.lowercased() == "converted"
        Button {
            showConvertSheet = true
        } label: {
            Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
        }
        .disabled(isConverted)
        .accessibilityLabel(isConverted ? "Already converted to ticket" : "Convert estimate to a service ticket")

        Divider()

        // Duplicate (route not yet available server-side)
        Button {
            // TODO: call POST /api/v1/estimates/:id/duplicate when endpoint ships
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        .disabled(true)
        .accessibilityLabel("Duplicate estimate — not yet available")

        // Archive (route not yet available server-side)
        Button(role: .destructive) {
            // TODO: call PATCH /api/v1/estimates/:id/archive when endpoint ships
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .disabled(true)
        .accessibilityLabel("Archive estimate — not yet available")
    }
}

// MARK: - ContextMenu Sheet Host
//
// Because .contextMenu { } is a ViewBuilder that runs inside a List row, we
// need a separate host view to own the @State for presented sheets.
// Attach this modifier to the row to get full sheet presentation.

public struct EstimateContextMenuHost<Content: View>: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onTicketCreated: @MainActor (Int64) -> Void
    private let content: Content

    @State private var showSignSheet = false
    @State private var showConvertSheet = false

    public init(
        estimate: Estimate,
        api: APIClient,
        onTicketCreated: @escaping @MainActor (Int64) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.estimate = estimate
        self.api = api
        self.onTicketCreated = onTicketCreated
        self.content = content()
    }

    public var body: some View {
        content
            .contextMenu {
                contextMenuItems
            }
            .sheet(isPresented: $showSignSheet) {
                EstimateSignSheet(
                    estimateId: estimate.id,
                    orderId: estimate.orderId ?? "EST-?",
                    api: api
                )
            }
            .sheet(isPresented: $showConvertSheet) {
                EstimateConvertSheet(
                    estimate: estimate,
                    api: api,
                    onSuccess: { ticketId in
                        showConvertSheet = false
                        onTicketCreated(ticketId)
                    }
                )
            }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            // Open: selection handled by parent binding
        } label: {
            Label("Open", systemImage: "doc.text.magnifyingglass")
        }
        .accessibilityLabel("Open estimate \(estimate.orderId ?? "")")

        Divider()

        let isSigned = estimate.status?.lowercased() == "signed"
        Button {
            showSignSheet = true
        } label: {
            Label(
                isSigned ? "Already Signed" : "Send for Signature",
                systemImage: isSigned ? "checkmark.seal.fill" : "pencil.and.signature"
            )
        }
        .disabled(isSigned)

        let isConverted = estimate.status?.lowercased() == "converted"
        Button {
            showConvertSheet = true
        } label: {
            Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
        }
        .disabled(isConverted)

        Divider()

        Button {
            // TODO: duplicate endpoint
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        .disabled(true)

        Button(role: .destructive) {
            // TODO: archive endpoint
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .disabled(true)
    }
}

#endif
