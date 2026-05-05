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
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: iso) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        return iso
    }
}
