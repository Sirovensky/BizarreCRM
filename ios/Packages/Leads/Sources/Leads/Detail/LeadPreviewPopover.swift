import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.1 Lead preview popover (iPad / Mac hover)

/// A compact popover surfaced on hover (`.hoverEffect`) or long-press
/// on iPad and Mac. Shows the core quick-stats for a lead without
/// navigating to the full detail screen.
///
/// Usage:
/// ```swift
/// LeadRow(lead: lead)
///     .modifier(LeadPreviewPopoverModifier(lead: lead, api: api))
/// ```
public struct LeadPreviewPopover: View {
    public let lead: Lead
    public let api: APIClient

    public init(lead: Lead, api: APIClient) {
        self.lead = lead
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            // Header: name + score
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(lead.displayName)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    if let company = lead.company, !company.isEmpty {
                        Text(company)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: BrandSpacing.sm)
                if let score = lead.leadScore {
                    LeadScoreBadge(score: score)
                }
            }

            Divider().overlay(Color.bizarreOutline.opacity(0.3))

            // Contact quick-stats
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                if let phone = lead.phone, !phone.isEmpty {
                    statRow(icon: "phone.fill", text: PhoneFormatter.format(phone))
                }
                if let email = lead.email, !email.isEmpty {
                    statRow(icon: "envelope.fill", text: email)
                        .textSelection(.enabled)
                }
                if let status = lead.status, !status.isEmpty {
                    statRow(icon: "arrow.triangle.2.circlepath", text: status.capitalized)
                }
                if let source = lead.source, !source.isEmpty {
                    statRow(icon: "link", text: source.capitalized)
                }
                if let assigned = lead.assignedDisplayName, !assigned.isEmpty {
                    statRow(icon: "person.fill", text: "Assigned: \(assigned)")
                }
            }

            // Quick actions (iPhone omits via isCompact guard)
            if !Platform.isCompact {
                Divider().overlay(Color.bizarreOutline.opacity(0.3))
                quickActions
            }
        }
        .padding(BrandSpacing.base)
        .frame(width: 280)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Views

    private func statRow(icon: String, text: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
        }
    }

    private var quickActions: some View {
        HStack(spacing: BrandSpacing.sm) {
            if let phone = lead.phone, !phone.isEmpty {
                quickActionChip(icon: "phone.fill", label: "Call") {
                    if let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
            }
            if let phone = lead.phone, !phone.isEmpty {
                quickActionChip(icon: "message.fill", label: "SMS") {
                    if let url = URL(string: "sms:\(phone.filter(\.isNumber))") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func quickActionChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreSurface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(lead.displayName)")
        .hoverEffect(.highlight)
    }

}

// MARK: - Lead assigned name helper

private extension Lead {
    var assignedDisplayName: String? {
        let parts = [assignedFirstName, assignedLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    var company: String? { nil } // placeholder — not in server model yet
}

// MARK: - ViewModifier

/// Attaches a `LeadPreviewPopover` hover popover to any view (iPad/Mac only).
/// On iPhone the modifier is a no-op so the same row code works everywhere.
public struct LeadPreviewPopoverModifier: ViewModifier {
    let lead: Lead
    let api: APIClient
    @State private var showingPopover = false

    public init(lead: Lead, api: APIClient) {
        self.lead = lead
        self.api = api
    }

    public func body(content: Content) -> some View {
        if Platform.isCompact {
            content
        } else {
            content
                .onHover { hovering in showingPopover = hovering }
                .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
                    LeadPreviewPopover(lead: lead, api: api)
                        .fixedSize()
                }
        }
    }
}
