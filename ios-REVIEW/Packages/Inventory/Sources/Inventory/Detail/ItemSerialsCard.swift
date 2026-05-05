#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.2 Serials in item detail
// Shows assigned serial numbers + which customer / ticket holds each.
// Only rendered when item.isSerialized == 1.

public struct ItemSerialsCard: View {
    let itemId: Int64
    let sku: String?
    let api: APIClient?

    @State private var serials: [SerializedItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    public init(itemId: Int64, sku: String?, api: APIClient?) {
        self.itemId = itemId
        self.sku = sku
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Serials", systemImage: "barcode")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .accessibilityLabel("Loading serial numbers")
            } else if let err = errorMessage {
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
            } else if serials.isEmpty {
                Text("No serial numbers recorded yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No serial numbers recorded")
            } else {
                VStack(spacing: BrandSpacing.xs) {
                    ForEach(serials.prefix(25)) { serial in
                        SerialRow(serial: serial)
                    }
                    if serials.count > 25 {
                        Text("+ \(serials.count - 25) more serials — use Serial Trace for full list.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .padding(.top, BrandSpacing.xxs)
                    }
                }
            }
        }
        .cardBackground()
        .task { await loadSerials() }
    }

    private func loadSerials() async {
        guard let api, let sku, !sku.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            serials = try await api.listSerials(parentSKU: sku)
        } catch {
            AppLog.ui.error("ItemSerialsCard load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't load serials: \(error.localizedDescription)"
        }
    }
}

// MARK: - Serial row

private struct SerialRow: View {
    let serial: SerializedItem

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(serial.serialNumber)
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                HStack(spacing: BrandSpacing.sm) {
                    statusChip
                    if let inv = serial.invoiceId {
                        Text("Invoice #\(inv)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let sold = serial.soldAt {
                        Text(formatDate(sold))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(serial.serialNumber), \(serial.status.displayName)\(serial.invoiceId.map { ", invoice \($0)" } ?? "")")
    }

    private var statusColor: Color {
        switch serial.status {
        case .available:  return .bizarreSuccess
        case .reserved:   return .bizarreWarning
        case .sold:       return .bizarreError
        case .returned:   return .bizarreOnSurfaceMuted
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        Text(serial.status.displayName)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.black)
            .background(statusColor.opacity(0.8), in: Capsule())
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: d)
    }
}

#endif
