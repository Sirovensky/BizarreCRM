#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §4.2 Warranty / SLA badge
//
// Shows either:
//   "Under warranty" (green badge) — when warrantyRecord is non-nil and in-warranty
//   "Warranty expired" (red badge) — when warrantyRecord is non-nil and expired
//   "X days to SLA breach" (amber/red) — derived from slaStatus on ticket summary
//   Hidden — when no warranty or SLA info is available
//
// Loaded by TicketDetailView on appear via GET /tickets/warranty-lookup.

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketWarrantySLAViewModel {
    public enum WarrantyState: Sendable {
        case loading
        case underWarranty(label: String)
        case warrantyExpired
        case noWarranty
        case error
    }

    public private(set) var warrantyState: WarrantyState = .loading
    public var slaStatus: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ticketId: Int64
    @ObservationIgnored private let imei: String?
    @ObservationIgnored private let serial: String?

    public init(api: APIClient, ticketId: Int64, imei: String? = nil, serial: String? = nil) {
        self.api = api
        self.ticketId = ticketId
        self.imei = imei
        self.serial = serial
    }

    // MARK: - Private helpers

    private func parseISO8601(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    // MARK: - Load

    public func load() async {
        guard imei != nil || serial != nil else {
            warrantyState = .noWarranty
            return
        }
        do {
            if let record = try await api.warrantyLookup(imei: imei, serial: serial) {
                let eligible = record.isEligible ?? false
                if eligible {
                    // Calculate days remaining from expiresAt if available, else show generic label
                    let label: String
                    if let expiresAt = record.expiresAt,
                       let expiry = parseISO8601(expiresAt) {
                        let days = Calendar.current.dateComponents(
                            [.day], from: Date(), to: expiry
                        ).day ?? 0
                        label = days <= 0 ? "Expires today" : "\(days)d left"
                    } else {
                        label = record.partName ?? "Active"
                    }
                    warrantyState = .underWarranty(label: label)
                } else {
                    warrantyState = .warrantyExpired
                }
            } else {
                warrantyState = .noWarranty
            }
        } catch {
            AppLog.ui.error("Warranty lookup failed: \(error.localizedDescription, privacy: .public)")
            warrantyState = .error
        }
    }
}

// MARK: - Badge view

/// Compact glass badge shown in the ticket detail header below the urgency chip.
public struct TicketWarrantySLABadge: View {
    private let slaStatus: String?
    private let warrantyState: TicketWarrantySLAViewModel.WarrantyState

    public init(
        slaStatus: String?,
        warrantyState: TicketWarrantySLAViewModel.WarrantyState
    ) {
        self.slaStatus = slaStatus
        self.warrantyState = warrantyState
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            warrantyBadge
            slaBadge
        }
    }

    // MARK: - Warranty badge

    @ViewBuilder
    private var warrantyBadge: some View {
        switch warrantyState {
        case .underWarranty(let label):
            badge(
                icon: "checkmark.shield.fill",
                text: "Under warranty · \(label)",
                foreground: .bizarreSuccess,
                background: Color.bizarreSuccess.opacity(0.12)
            )
            .accessibilityLabel("Under warranty. \(label)")
        case .warrantyExpired:
            badge(
                icon: "xmark.shield",
                text: "Warranty expired",
                foreground: .bizarreError,
                background: Color.bizarreError.opacity(0.12)
            )
            .accessibilityLabel("Warranty expired")
        case .loading, .noWarranty, .error:
            EmptyView()
        }
    }

    // MARK: - SLA badge

    @ViewBuilder
    private var slaBadge: some View {
        if let sla = slaStatus, !sla.isEmpty {
            let config = slaConfig(for: sla)
            badge(
                icon: config.icon,
                text: sla,
                foreground: config.foreground,
                background: config.background
            )
            // §4.1 a11y: expose urgency tier explicitly so VoiceOver users
            // don't just hear the raw server string (e.g. "breached") but a
            // human-readable sentence with the severity.
            .accessibilityLabel(slaAccessibilityLabel(for: sla))
            .accessibilityAddTraits(slaIsUrgent(sla) ? [.updatesFrequently] : [])
        }
    }

    private func slaAccessibilityLabel(for status: String) -> String {
        let lower = status.lowercased()
        if lower.contains("breach") || lower.contains("overdue") || lower.contains("red") {
            return "SLA breached. Immediate action required."
        }
        if lower.contains("warn") || lower.contains("amber") || lower.contains("due soon") {
            return "SLA warning. Due soon."
        }
        return "SLA on track."
    }

    private func slaIsUrgent(_ status: String) -> Bool {
        let lower = status.lowercased()
        return lower.contains("breach") || lower.contains("overdue") || lower.contains("warn") || lower.contains("amber")
    }

    // MARK: - Badge helper

    private func badge(
        icon: String,
        text: String,
        foreground: Color,
        background: Color
    ) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foreground)
                .accessibilityHidden(true)
            Text(text)
                .font(.brandLabelSmall())
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(background, in: Capsule())
    }

    // MARK: - SLA color logic

    private struct SLAConfig {
        let icon: String
        let foreground: Color
        let background: Color
    }

    private func slaConfig(for status: String) -> SLAConfig {
        let lower = status.lowercased()
        if lower.contains("breach") || lower.contains("overdue") || lower.contains("red") {
            return SLAConfig(icon: "exclamationmark.circle.fill",
                             foreground: .bizarreError,
                             background: Color.bizarreError.opacity(0.12))
        }
        if lower.contains("warn") || lower.contains("amber") || lower.contains("due soon") {
            return SLAConfig(icon: "clock.badge.exclamationmark",
                             foreground: .bizarreWarning,
                             background: Color.bizarreWarning.opacity(0.12))
        }
        return SLAConfig(icon: "clock",
                         foreground: .bizarreSuccess,
                         background: Color.bizarreSuccess.opacity(0.12))
    }
}
#endif
