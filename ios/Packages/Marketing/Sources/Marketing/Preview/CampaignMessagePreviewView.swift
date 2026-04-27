import SwiftUI
import Core
import DesignSystem

// MARK: - §37 Campaign message preview
// iPhone-bubble rendering for SMS + HTML render for email with dynamic-variable substitution.

/// Renders a live preview of a campaign message body as it will appear to recipients.
/// For SMS: renders as a phone-style message bubble with dynamic vars substituted.
/// For email: renders as a simplified HTML preview card.
public struct CampaignMessagePreviewView: View {
    let messageBody: String
    let channel: CampaignPreviewChannel
    /// Sample values used to substitute dynamic vars in preview.
    let sampleContext: [String: String]

    public enum CampaignPreviewChannel: String, CaseIterable, Sendable {
        case sms
        case email
    }

    public init(
        messageBody: String,
        channel: CampaignPreviewChannel,
        sampleContext: [String: String] = CampaignMessagePreviewView.defaultContext
    ) {
        self.messageBody = messageBody
        self.channel = channel
        self.sampleContext = sampleContext
    }

    /// Default preview sample values for all known dynamic variables.
    public static let defaultContext: [String: String] = [
        "first_name":      "Alex",
        "last_name":       "Smith",
        "shop_name":       "BizarreCRM Demo",
        "ticket_no":       "TKT-0042",
        "amount":          "$129.00",
        "due_date":        "May 5, 2026",
        "tech_name":       "Sam T.",
        "appointment_time":"Fri at 2 PM",
        "coupon_code":     "SAVE10",
    ]

    private var renderedBody: String {
        TemplateVariableRenderer.render(template: messageBody, context: sampleContext)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.base) {
            // Channel picker header
            HStack {
                Image(systemName: channel == .sms ? "iphone" : "envelope.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(channel == .sms ? "SMS Preview" : "Email Preview")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Text("Sample data")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .italic()
            }

            if channel == .sms {
                smsBubblePreview
            } else {
                emailCardPreview
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - SMS bubble

    private var smsBubblePreview: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Simulated phone screen chrome
            HStack {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 14))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text(sampleContext["shop_name"] ?? "Shop")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Business")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)

            // Message bubble (incoming style — outbound from business perspective)
            HStack(alignment: .bottom, spacing: BrandSpacing.xs) {
                Spacer(minLength: 24)
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text(renderedBody)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.white)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(Color.bizarreOrange, in: BubbleShape(isOutgoing: true))
                        .accessibilityLabel("Message preview: \(renderedBody)")

                    Text("Delivered")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.trailing, BrandSpacing.xs)
                }
            }

            // Segment character count
            let segments = SMSSegmentCalculator.segments(for: renderedBody)
            Text("\(renderedBody.count) chars · \(segments) SMS segment\(segments == 1 ? "" : "s")")
                .font(.brandLabelSmall())
                .foregroundStyle(segments > 3 ? .bizarreWarning : .bizarreOnSurfaceMuted)
                .accessibilityLabel("Message is \(renderedBody.count) characters, \(segments) SMS segments")
        }
    }

    // MARK: - Email card

    private var emailCardPreview: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Mock email header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("From:")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 44, alignment: .leading)
                    Text(sampleContext["shop_name"] ?? "Shop")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                HStack {
                    Text("To:")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 44, alignment: .leading)
                    Text("\(sampleContext["first_name"] ?? "Alex") \(sampleContext["last_name"] ?? "Smith") <alex@example.com>")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                }
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            Divider()

            // Email body
            Text(renderedBody)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.vertical, BrandSpacing.xs)
                .accessibilityLabel("Email body preview: \(renderedBody)")

            // Unsubscribe footer
            Divider()
            Text("You received this because you opted in. Unsubscribe · Manage preferences")
                .font(.system(size: 10))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(BrandSpacing.sm)
    }
}

// MARK: - Bubble shape

private struct BubbleShape: Shape {
    let isOutgoing: Bool
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailW: CGFloat = 8
        var p = Path()
        if isOutgoing {
            p.addRoundedRect(in: CGRect(x: 0, y: 0, width: rect.width - tailW, height: rect.height), cornerSize: CGSize(width: radius, height: radius))
        } else {
            p.addRoundedRect(in: CGRect(x: tailW, y: 0, width: rect.width - tailW, height: rect.height), cornerSize: CGSize(width: radius, height: radius))
        }
        return p
    }
}

// MARK: - Template renderer

/// Simple `{variable}` substitution used for message previews.
public struct TemplateVariableRenderer {
    public static func render(template: String, context: [String: String]) -> String {
        var result = template
        for (key, value) in context {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
                           .replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}

// MARK: - SMS segment calculator

/// Computes SMS segment count (160 chars GSM-7 / 70 chars unicode).
public struct SMSSegmentCalculator {
    public static func segments(for body: String) -> Int {
        let isGSM = body.unicodeScalars.allSatisfy { isGSM7($0.value) }
        let limit  = isGSM ? 160 : 70
        let multi  = isGSM ? 153 : 67
        let count  = body.count
        guard count > 0 else { return 0 }
        if count <= limit { return 1 }
        return Int(ceil(Double(count) / Double(multi)))
    }

    private static func isGSM7(_ scalar: UInt32) -> Bool {
        let gsm7: [UInt32] = [
            0x40,0xA3,0x24,0xA5,0xE8,0xE9,0xF9,0xEC,0xF2,0xC7,
            0x0A,0xD8,0xF8,0x0D,0xC5,0xE5,0x20,0x21,0x22,0x23,
            0xA4,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,0x2C,0x2D,
            0x2E,0x2F,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,0xA1,0xC6,
            0xE6,0xDF,0xC9,0x30,0x31,0x32,0x33,0x34,0x35,0x36,
            0x37,0x38,0x39,0xD1,0xF1,0xC0,0xC1,0xC2,0xC3,0xC4,
        ]
        return (scalar >= 0x41 && scalar <= 0x5A) ||
               (scalar >= 0x61 && scalar <= 0x7A) ||
               gsm7.contains(scalar)
    }
}
