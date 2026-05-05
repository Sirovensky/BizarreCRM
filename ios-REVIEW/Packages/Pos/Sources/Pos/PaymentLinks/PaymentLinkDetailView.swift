#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking

// MARK: - §41 Payment Link Detail View

/// Full detail screen for a single payment link. Shows:
///   - Status badge (active / paid / expired / cancelled)
///   - Amount + description
///   - Opens / click counts (from server `click_count` / `last_clicked_at`)
///   - QR code (via `BrandedQRGenerator`)
///   - Copy URL + Share buttons
///   - Cancel swipe action when active
///
/// iPhone: full-screen NavigationStack push.
/// iPad: detail pane in NavigationSplitView; `.hoverEffect` on tappable rows.
public struct PaymentLinkDetailView: View {
    @State private var vm: PaymentLinkDetailViewModel
    @State private var showingShare: Bool = false
    @State private var showCopiedToast: Bool = false

    public init(link: PaymentLink, api: APIClient) {
        _vm = State(wrappedValue: PaymentLinkDetailViewModel(link: link, api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.link.id == 0 {
                ProgressView()
            } else {
                content
            }
        }
        .navigationTitle("Payment link")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if Platform.isCompact {
                // iPhone: cancel in toolbar when active.
                if vm.link.isActive {
                    ToolbarItem(placement: .primaryAction) {
                        cancelButton
                            .brandGlass(.regular, in: Capsule(), interactive: true)
                    }
                }
            }
        }
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
        .overlay(alignment: .bottom) {
            if showCopiedToast { copiedToast }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if Platform.isCompact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: iPhone

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                statusHeader
                qrSection
                statsSection
                urlSection
                actionRow
                if vm.link.isActive {
                    cancelSection
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.lg)
        }
    }

    // MARK: iPad

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.xl) {
            // Left: QR + action row
            VStack(spacing: BrandSpacing.lg) {
                qrSection
                actionRow
                if vm.link.isActive {
                    cancelSection
                }
            }
            .frame(maxWidth: 320)

            // Right: status + stats + URL
            VStack(spacing: BrandSpacing.lg) {
                statusHeader
                statsSection
                urlSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BrandSpacing.xl)
    }

    // MARK: - Subviews

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            PaymentLinkStatusChip(status: vm.link.statusKind)
            VStack(alignment: .leading, spacing: 2) {
                Text(CartMath.formatCents(vm.link.amountCents))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                if let desc = vm.link.description, !desc.isEmpty {
                    Text(desc)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }

    private var qrSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            if vm.link.url.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bizarreSurface1)
                    .frame(width: 200, height: 200)
                    .overlay {
                        ProgressView()
                    }
            } else {
                QRCodeView(
                    urlString: vm.link.url,
                    size: 200
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                .accessibilityLabel("QR code for payment link")
                .accessibilityIdentifier("paymentLinks.detail.qr")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsSection: some View {
        HStack(spacing: BrandSpacing.md) {
            StatCell(
                icon: "eye",
                value: "\(vm.clickCount)",
                label: "Clicks"
            )
            .hoverEffect(.highlight)
            Divider()
                .frame(height: 36)
            StatCell(
                icon: "clock",
                value: vm.lastClickedLabel,
                label: "Last click"
            )
            .hoverEffect(.highlight)
            if let paidAt = vm.link.paidAt {
                Divider()
                    .frame(height: 36)
                StatCell(
                    icon: "checkmark.seal.fill",
                    value: shortDateLabel(paidAt),
                    label: "Paid"
                )
                .hoverEffect(.highlight)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Pay URL")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(vm.link.url.isEmpty ? "(building URL…)" : vm.link.url)
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .textSelection(.enabled)
                .accessibilityIdentifier("paymentLinks.detail.url")
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }

    private var actionRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button {
                UIPasteboard.general.string = vm.link.url
                BrandHaptics.tap()
                showCopiedToast = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    showCopiedToast = false
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.bizarreOrange)
            .disabled(vm.link.url.isEmpty)
            .accessibilityIdentifier("paymentLinks.detail.copyButton")
            .hoverEffect(.highlight)

            Button {
                BrandHaptics.tap()
                showingShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(vm.link.url.isEmpty)
            .accessibilityIdentifier("paymentLinks.detail.shareButton")
            .hoverEffect(.highlight)
        }
        .controlSize(.large)
        .sheet(isPresented: $showingShare) {
            PosShareSheet(items: [vm.link.url])
        }
    }

    private var cancelSection: some View {
        VStack(spacing: BrandSpacing.xs) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("paymentLinks.detail.error")
            }
            cancelButton
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
        }
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            BrandHaptics.tapMedium()
            Task { await vm.cancel() }
        } label: {
            if vm.isCancelling {
                Label("Cancelling…", systemImage: "xmark.circle")
            } else {
                Label("Cancel link", systemImage: "xmark.circle")
            }
        }
        .disabled(vm.isCancelling)
        .accessibilityIdentifier("paymentLinks.detail.cancelButton")
    }

    private var copiedToast: some View {
        Text("Copied to clipboard")
            .font(.brandLabelLarge())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.black.opacity(0.85), in: Capsule())
            .padding(.bottom, BrandSpacing.xl)
            .transition(.opacity)
    }

    // MARK: - Helpers

    private func shortDateLabel(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .none
            return df.string(from: d)
        }
        // Fallback without fractional seconds.
        let fmt2 = ISO8601DateFormatter()
        fmt2.formatOptions = [.withInternetDateTime]
        if let d = fmt2.date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .short
            return df.string(from: d)
        }
        return iso.prefix(10).description
    }
}

// MARK: - QRCodeView

/// Wraps `BrandedQRGenerator` so `PaymentLinkDetailView` stays declarative.
private struct QRCodeView: View {
    let urlString: String
    let size: CGFloat

    var body: some View {
        if let img = BrandedQRGenerator.generate(urlString: urlString, size: size) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bizarreSurface1)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "qrcode")
                        .font(.system(size: 60))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
        }
    }
}

// MARK: - StatCell

private struct StatCell: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
            Text(value)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ViewModel

/// Observable view-model for `PaymentLinkDetailView`.
///
/// Re-fetches the row on `.task` / `.refreshable`. Reads `click_count` /
/// `last_clicked_at` from the raw JSON via a thin `PaymentLinkDetailRow`
/// shim so the base `PaymentLink` DTO (which the server does return these
/// on the `:id` endpoint) can be extended without touching the Networking
/// package.
@MainActor
@Observable
public final class PaymentLinkDetailViewModel {
    public private(set) var link: PaymentLink
    /// Server `click_count` column — populated after the first reload.
    public private(set) var clickCount: Int = 0
    /// ISO-8601 string for `last_clicked_at` — nil until first reload.
    public private(set) var lastClickedAt: String?
    public private(set) var isLoading: Bool = false
    public private(set) var isCancelling: Bool = false
    public private(set) var errorMessage: String?

    private let api: APIClient

    public init(link: PaymentLink, api: APIClient) {
        self.link = link
        self.api = api
    }

    /// Human-readable label for the last-click timestamp.
    public var lastClickedLabel: String {
        guard let raw = lastClickedAt else { return "—" }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = fmt.date(from: raw) ?? {
            var f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return f2.date(from: raw)
        }()
        guard let d else { return raw.prefix(10).description }
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: d)
    }

    // MARK: - Actions

    public func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            // Use the authed GET /:id endpoint which returns the full row.
            let refreshed = try await api.getPaymentLink(id: link.id)
            link = refreshed
            // Also fetch the raw envelope to pull extra columns that the
            // base DTO doesn't decode (click_count, last_clicked_at).
            let raw = try await api.getEnvelope(
                "/api/v1/payment-links/\(link.id)",
                query: nil,
                as: PaymentLinkDetailRow.self
            )
            if let row = raw.data {
                clickCount = row.clickCount ?? 0
                lastClickedAt = row.lastClickedAt
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load payment link."
        }
        isLoading = false
    }

    public func cancel() async {
        guard link.isActive else { return }
        isCancelling = true
        errorMessage = nil
        do {
            try await api.cancelPaymentLink(id: link.id)
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not cancel payment link."
        }
        isCancelling = false
    }
}

// MARK: - PaymentLinkDetailRow

/// Thin shim to decode server columns not present in the base `PaymentLink`
/// DTO. Used only by `PaymentLinkDetailViewModel` to enrich the detail screen.
public struct PaymentLinkDetailRow: Decodable, Sendable {
    public let clickCount: Int?
    public let lastClickedAt: String?

    enum CodingKeys: String, CodingKey {
        case clickCount    = "click_count"
        case lastClickedAt = "last_clicked_at"
    }
}
#endif
