import SwiftUI
import DesignSystem

// MARK: - §3.14 Per-card empty states when a section has zero data.
//
// These views are used as fallbacks inside each dashboard section when
// a new tenant has no data yet. Each card has a distinct illustration
// (SF Symbol composition) and a tailored CTA.
//
// Design rules:
//   - No glass on content (CLAUDE.md §glass-rules).
//   - Surface1 background card.
//   - Horizontal padding consistent with sibling KPI cards.

// MARK: - Shared shape

private struct EmptyStateCard<Icon: View>: View {
    let icon: Icon
    let headline: String
    let body: String
    let ctaLabel: String?
    let onCTA: (() -> Void)?

    init(
        @ViewBuilder icon: () -> Icon,
        headline: String,
        body: String,
        ctaLabel: String? = nil,
        onCTA: (() -> Void)? = nil
    ) {
        self.icon = icon()
        self.headline = headline
        self.body = body
        self.ctaLabel = ctaLabel
        self.onCTA = onCTA
    }

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            icon
                .accessibilityHidden(true)

            Text(headline)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(body)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)

            if let label = ctaLabel, let action = onCTA {
                Button(action: action) {
                    Text(label)
                        .font(.brandBodyMedium().weight(.semibold))
                        .foregroundStyle(.bizarreOnSurface)
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(.bizarreOrange.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("emptyState.cta.\(label.lowercased().replacing(" ", with: "_"))")
            }
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg))
    }
}

// MARK: - §3.14.1 Tickets empty

/// Empty state for the Tickets section when no tickets exist yet.
public struct TicketsSectionEmptyState: View {
    public var onCreateTicket: (() -> Void)?
    public var onImport: (() -> Void)?

    public init(
        onCreateTicket: (() -> Void)? = nil,
        onImport: (() -> Void)? = nil
    ) {
        self.onCreateTicket = onCreateTicket
        self.onImport = onImport
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            EmptyStateCard(
                icon: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 40))
                        .foregroundStyle(.bizarreOrange.opacity(0.8))
                        .symbolEffect(.pulse, isActive: false)
                },
                headline: "No tickets yet",
                body: "Tickets track every repair job. Create your first one or import your existing data.",
                ctaLabel: "Create your first ticket",
                onCTA: onCreateTicket
            )

            if let importAction = onImport {
                Button(action: importAction) {
                    Text("Or import from old system")
                        .font(.brandLabelMedium())
                        .foregroundStyle(.bizarreOrange)
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tickets.emptyState.import")
            }
        }
    }
}

// MARK: - §3.14.2 Inventory empty

/// Empty state for the Inventory section when no products exist.
public struct InventorySectionEmptyState: View {
    public var onAddProduct: (() -> Void)?
    public var onImportCatalog: (() -> Void)?

    public init(
        onAddProduct: (() -> Void)? = nil,
        onImportCatalog: (() -> Void)? = nil
    ) {
        self.onAddProduct = onAddProduct
        self.onImportCatalog = onImportCatalog
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            EmptyStateCard(
                icon: {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 40))
                        .foregroundStyle(.bizarreTeal.opacity(0.8))
                },
                headline: "No inventory yet",
                body: "Add your first product or import a parts catalog to start tracking stock.",
                ctaLabel: "Add your first product",
                onCTA: onAddProduct
            )

            if let importAction = onImportCatalog {
                Button(action: importAction) {
                    Text("Import catalog (CSV)")
                        .font(.brandLabelMedium())
                        .foregroundStyle(.bizarreTeal)
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inventory.emptyState.import")
            }
        }
    }
}

// MARK: - §3.14.3 Customers empty

/// Empty state for the Customers section when no customers exist.
public struct CustomersSectionEmptyState: View {
    public var onAddCustomer: (() -> Void)?
    public var onImportContacts: (() -> Void)?

    public init(
        onAddCustomer: (() -> Void)? = nil,
        onImportContacts: (() -> Void)? = nil
    ) {
        self.onAddCustomer = onAddCustomer
        self.onImportContacts = onImportContacts
    }

    public var body: some View {
        EmptyStateCard(
            icon: {
                Image(systemName: "person.2")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreMagenta.opacity(0.8))
            },
            headline: "No customers yet",
            body: "Customers are the heart of your shop. Add your first customer or import from Contacts.",
            ctaLabel: "Add first customer",
            onCTA: onAddCustomer
        )
    }
}

// MARK: - §3.14.4 SMS empty

/// Empty state for the SMS section when SMS is not yet connected.
public struct SMSSectionEmptyState: View {
    public var onConnectSMS: (() -> Void)?

    public init(onConnectSMS: (() -> Void)? = nil) {
        self.onConnectSMS = onConnectSMS
    }

    public var body: some View {
        EmptyStateCard(
            icon: {
                Image(systemName: "message.badge.waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreOrange.opacity(0.8))
            },
            headline: "SMS not connected",
            body: "Connect an SMS provider to message customers directly from the app.",
            ctaLabel: "Connect SMS provider",
            onCTA: onConnectSMS
        )
    }
}

// MARK: - §3.14.5 POS empty

/// Empty state for the POS section when payment hardware is not configured.
public struct POSSectionEmptyState: View {
    public var onConnectBlockChyp: (() -> Void)?
    public var onEnableCashOnly: (() -> Void)?

    public init(
        onConnectBlockChyp: (() -> Void)? = nil,
        onEnableCashOnly: (() -> Void)? = nil
    ) {
        self.onConnectBlockChyp = onConnectBlockChyp
        self.onEnableCashOnly = onEnableCashOnly
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            EmptyStateCard(
                icon: {
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 40))
                        .foregroundStyle(.bizarreOrange.opacity(0.8))
                },
                headline: "Payment not configured",
                body: "Connect BlockChyp to take card payments, or enable cash-only mode to get started right away.",
                ctaLabel: "Connect BlockChyp",
                onCTA: onConnectBlockChyp
            )

            if let cashAction = onEnableCashOnly {
                Button(action: cashAction) {
                    Text("Cash-only POS (no hardware needed)")
                        .font(.brandLabelMedium())
                        .foregroundStyle(.bizarreOrange)
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pos.emptyState.cashOnly")
            }
        }
    }
}

// MARK: - §3.14.6 Reports empty

/// Empty state for the Reports section when no sales data exists.
public struct ReportsSectionEmptyState: View {
    public init() {}

    public var body: some View {
        EmptyStateCard(
            icon: {
                ZStack {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 38))
                        .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.3))
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.15))
                        .offset(x: 8, y: 4)
                }
            },
            headline: "No data yet",
            body: "Reports populate once you record your first sale. Come back after your first transaction.",
            ctaLabel: nil,
            onCTA: nil
        )
    }
}

// MARK: - §3.14.7 KPI "No data yet" tile

/// Inline empty state for individual KPI tiles with zero data.
public struct KPINoDataOverlay: View {
    public var onboardingAction: (() -> Void)?
    public let message: String

    public init(message: String = "No data yet", onboardingAction: (() -> Void)? = nil) {
        self.message = message
        self.onboardingAction = onboardingAction
    }

    public var body: some View {
        if let action = onboardingAction {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double tap to start onboarding")
        } else {
            label
        }
    }

    private var label: some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.callout)
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.6))
                .accessibilityHidden(true)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(message)
    }
}

#if DEBUG
#Preview("Tickets Empty") {
    TicketsSectionEmptyState(
        onCreateTicket: { print("create") },
        onImport: { print("import") }
    )
    .padding()
}

#Preview("Reports Empty") {
    ReportsSectionEmptyState()
        .padding()
}

#Preview("KPI No Data") {
    KPINoDataOverlay(message: "No data yet", onboardingAction: { print("onboarding") })
        .frame(height: 80)
        .padding()
}
#endif
