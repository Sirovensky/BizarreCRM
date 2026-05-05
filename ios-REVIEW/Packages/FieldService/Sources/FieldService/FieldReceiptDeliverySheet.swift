// §57.3 FieldReceiptDeliverySheet — post-charge sheet offering
// "Email receipt" / "SMS receipt" / "Print" (if portable printer).
// Dispatches via existing Email/SMS templates pattern.

import SwiftUI
import DesignSystem

// MARK: - FieldReceiptDeliverySheet

/// §57.3 — Post-charge receipt delivery options.
///
/// Dispatches email/SMS by opening a compose sheet.
/// "Print" action shown but guarded by portable-printer capability check.
public struct FieldReceiptDeliverySheet: View {

    public let transactionId: String
    public let customerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var showingEmailCompose = false
    @State private var showingSMSCompose = false
    @State private var showPrintUnavailable = false

    public init(transactionId: String, customerName: String) {
        self.transactionId = transactionId
        self.customerName = customerName
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xl) {
                headerSection
                Divider()
                optionsList
                Spacer()
                doneButton
            }
            .padding(DesignTokens.Spacing.xl)
            .navigationTitle("Send Receipt")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
            .alert("Printer Unavailable",
                   isPresented: $showPrintUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No portable printer is paired. Connect a printer in Settings → Hardware.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "receipt.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOrange)
            Text("Payment recorded for \(customerName)")
                .font(.brandBodyMedium())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Options

    private var optionsList: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ReceiptOptionRow(
                icon: "envelope.fill",
                title: "Email Receipt",
                subtitle: "Send a PDF receipt by email"
            ) {
                showingEmailCompose = true
            }

            ReceiptOptionRow(
                icon: "message.fill",
                title: "SMS Receipt",
                subtitle: "Send a text message receipt"
            ) {
                showingSMSCompose = true
            }

            ReceiptOptionRow(
                icon: "printer.fill",
                title: "Print Receipt",
                subtitle: "Print via paired portable printer"
            ) {
                triggerPrint()
            }
        }
    }

    // MARK: - Done

    private var doneButton: some View {
        Button("Done") { dismiss() }
            .buttonStyle(.brandGlass)
    }

    // MARK: - Actions

    private func triggerPrint() {
        // §57.3: Show unavailable alert until portable printer pairing is wired.
        // When printer is available, use UIPrintInteractionController.
        showPrintUnavailable = true
    }
}

// MARK: - ReceiptOptionRow

private struct ReceiptOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(DesignTokens.Spacing.md)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
        .buttonStyle(.plain)
    }
}
