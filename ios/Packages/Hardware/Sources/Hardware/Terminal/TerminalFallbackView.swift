#if canImport(UIKit)
import SwiftUI
import Core

// §17.3 Fallback when terminal truly unreachable.
//
// Shown in the POS charge sheet when:
//   - `ChargeCoordinatorError.noTerminalPaired`, or
//   - `TerminalError.unreachable` after a ping attempt.
//
// Options offered:
//   a) Cash tender (always available — role check by POS layer).
//   b) Manual-keyed card — role-gated, PIN-protected, routes through
//      BlockChyp manual-entry API. Not available in offline mode.
//   c) Queue offline sale with "card pending" status (retry on reconnect).
//
// §17.3 requirement: Never build our own TextFields capturing PAN/expiry/CVV.
// That pushes the app into SAQ-D scope. Manual-keyed is handled by the
// BlockChyp terminal screen (customer enters on terminal), not in this app.

// MARK: - TerminalFallbackAction

public enum TerminalFallbackAction: Sendable, Hashable {
    /// Accept cash instead of card.
    case cashTender
    /// Offer manual-keyed card via BlockChyp terminal screen (role-gated).
    case manualKeyedCard
    /// Save a "card pending" offline sale for retry when terminal reconnects.
    case queueOfflineSale
}

// MARK: - TerminalFallbackView

/// Sheet shown when the card terminal is unreachable or not paired.
/// POS owner provides callbacks for each action.
public struct TerminalFallbackView: View {

    public let reason: String
    public let isOnline: Bool
    public let canManualKey: Bool // role-gated by caller
    public let onSelectAction: (TerminalFallbackAction) -> Void
    public let onDismiss: () -> Void

    public init(
        reason: String,
        isOnline: Bool,
        canManualKey: Bool,
        onSelectAction: @escaping (TerminalFallbackAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.reason = reason
        self.isOnline = isOnline
        self.canManualKey = canManualKey
        self.onSelectAction = onSelectAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Terminal Unavailable")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24)

                Divider()

                // Action options
                VStack(spacing: 16) {
                    // Cash tender — always available
                    FallbackOptionButton(
                        icon: "banknote",
                        title: "Accept Cash",
                        subtitle: "Tender the sale as cash payment.",
                        color: .green
                    ) {
                        onSelectAction(.cashTender)
                    }

                    // Manual-keyed — requires internet + role
                    if isOnline && canManualKey {
                        FallbackOptionButton(
                            icon: "keyboard",
                            title: "Manual Card Entry",
                            subtitle: "Customer enters card details on the terminal screen. Requires manager role.",
                            color: .blue
                        ) {
                            onSelectAction(.manualKeyedCard)
                        }
                    } else if !isOnline {
                        FallbackOptionButton(
                            icon: "keyboard",
                            title: "Manual Card Entry",
                            subtitle: "Not available offline — requires internet to tokenize.",
                            color: .gray,
                            isDisabled: true
                        ) {}
                    }

                    // Queue offline sale — only if the design allows deferred payment
                    FallbackOptionButton(
                        icon: "clock.badge.plus",
                        title: "Queue for Later",
                        subtitle: "Save as \"card pending\" — retry when terminal reconnects. Requires manager approval on pickup.",
                        color: .orange
                    ) {
                        onSelectAction(.queueOfflineSale)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Payment Fallback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .accessibilityLabel("Cancel payment fallback")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - FallbackOptionButton

private struct FallbackOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isDisabled ? .secondary : color)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if !isDisabled {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isDisabled ? .isStaticText : .isButton)
    }
}

// MARK: - NetworkRequirementsView (§17.3 setup wizard info screen)

/// Informational screen shown in the Setup Wizard → Hardware → BlockChyp step.
/// Explains firewall + network prerequisites for each relay mode.
public struct NetworkRequirementsView: View {

    public init() {}

    public var body: some View {
        List {
            Section {
                requirementRow(
                    icon: "globe",
                    title: "Cloud relay mode",
                    detail: "Firewall must allow outbound HTTPS to api.blockchyp.com (port 443). Works from any network — cellular, guest Wi-Fi, etc."
                )
                requirementRow(
                    icon: "wifi.router",
                    title: "Local mode",
                    detail: "iPad and terminal must be on the same subnet or a routed LAN reachable on the terminal's service port. No cloud dependency after terminal is provisioned."
                )
                requirementRow(
                    icon: "location.slash",
                    title: "True offline",
                    detail: "Local mode: charges may still succeed if the terminal's own uplink is up. Cloud-relay mode: no charges possible without internet. Check the mode badge in the charge sheet."
                )
            } header: {
                Text("Network Requirements")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Contact your IT team to verify these requirements before deploying to a new location.")
                    .font(.caption2)
            }

            Section("DHCP / Static IP") {
                requirementRow(
                    icon: "network.badge.shield.half.filled",
                    title: "Recommended",
                    detail: "Set a DHCP reservation for the terminal's MAC address so its IP doesn't change. The BlockChyp SDK re-discovers the IP automatically, but a stable address reduces latency."
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Network Setup")
        .navigationBarTitleDisplayMode(.large)
    }

    private func requirementRow(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.body)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }
}
#endif
