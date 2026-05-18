import SwiftUI
import Core
import DesignSystem

// MARK: - DeliveryReportView

/// Per-message delivery detail sheet: timestamp, carrier, failure reason.
/// iPhone: presented as a sheet. iPad: inline popover or split detail.
public struct DeliveryReportView: View {
    public let response: DeliveryStatusResponse

    public init(response: DeliveryStatusResponse) {
        self.response = response
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack {
            content
                .navigationTitle("Delivery Report")
#if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        content
            .frame(minWidth: 360)
    }

    // MARK: - Shared content

    private var content: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            List {
                Section {
                    reportRow(label: "Status", value: response.status.displayLabel, isError: response.status.isError)
                    if let at = response.deliveredAt {
                        reportRow(label: "Delivered at", value: formattedTimestamp(at))
                    }
                    if let carrier = response.carrier, !carrier.isEmpty {
                        reportRow(label: "Carrier", value: carrier)
                    }
                    if let reason = response.failureReason, !reason.isEmpty {
                        reportRow(label: "Failure reason", value: reason, isError: true)
                    }
                    reportRow(label: "Message ID", value: "#\(response.messageId)")
                } header: {
                    Text("Delivery Details")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Row

    private func reportRow(label: String, value: String, isError: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer(minLength: BrandSpacing.sm)
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(isError ? Color.bizarreError : Color.bizarreOnSurface)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Helpers

    private func formattedTimestamp(_ iso: String) -> String {
        // BUGHUNT-2026-05-18: previously only tried fractional ISO. Plain ISO
        // (no millisecond component, emitted by some server hand-built strings)
        // fell through to the raw display path, leaking "2026-05-18T10:30:45Z"
        // into the delivery report timeline instead of "May 18, 2026 at 10:30 AM."
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = frac.date(from: iso) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: iso) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        return iso
    }
}
