#if canImport(UIKit)
import SwiftUI
import Core

// MARK: - CashDrawerFallbackView
//
// §17.4 "Cash-drawer kick — via printer ESC command; if printer offline, surface
//  'Open drawer manually' button that logs an audit event so shift reconciliation
//  can show drawer-open vs sale counts."
//
// This view is shown in the POS totals footer when the paired printer is offline
// or no printer is configured, replacing the disabled "Open Drawer" button.
// Tapping the manual-open button records an audit event (POST /audit/events)
// so the Z-report can reconcile drawer-open occurrences against sales.

/// Displayed in place of the normal drawer-kick button when the printer is offline.
///
/// Usage:
/// ```swift
/// if !drawer.isConnected {
///     CashDrawerFallbackView(onManualOpen: {
///         await auditLogger.logDrawerManualOpen(receiptId: receipt.id)
///     })
/// }
/// ```
public struct CashDrawerFallbackView: View {

    // MARK: - Input

    /// Called after the user confirms they opened the drawer manually.
    /// Implementors should POST to the audit log endpoint.
    public let onManualOpen: () async -> Void

    // MARK: - State

    @State private var showConfirm: Bool = false
    @State private var isLogging: Bool = false
    @State private var didLog: Bool = false

    // MARK: - Init

    public init(onManualOpen: @escaping () async -> Void) {
        self.onManualOpen = onManualOpen
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "printer.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Printer offline — drawer kick unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if didLog {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Manual open logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Label("Open Drawer Manually", systemImage: "lock.open.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(isLogging)
                .accessibilityLabel("Open cash drawer manually and log the event")
                .accessibilityHint("Tap to confirm you opened the drawer by hand. The event will be logged for reconciliation.")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            "Open drawer manually?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Open Manually") {
                Task { await confirmManualOpen() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This event will be logged for shift reconciliation. The drawer will not open automatically — open it by hand.")
        }
        .animation(.easeInOut(duration: 0.2), value: didLog)
    }

    // MARK: - Action

    @MainActor
    private func confirmManualOpen() async {
        isLogging = true
        defer { isLogging = false }
        await onManualOpen()
        didLog = true
        AppLog.hardware.info("CashDrawerFallbackView: manual-open confirmed and logged")
        // Reset after 4 s so the button reappears for the next sale.
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        didLog = false
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Drawer offline fallback") {
    CashDrawerFallbackView(onManualOpen: {
        try? await Task.sleep(nanoseconds: 500_000_000)
    })
    .padding()
}
#endif

#endif
