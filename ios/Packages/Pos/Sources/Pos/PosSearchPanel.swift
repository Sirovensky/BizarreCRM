#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Inventory
import Networking

/// Item-picker column. Houses the search bar, the results list, and the
/// "Add custom line" entry point. On iPhone this sits under the cart; on
/// iPad it's the leading column of the split view.
///
/// §16.4: when no customer is yet attached to the cart, the empty state
/// also surfaces the three customer-attach CTAs (walk-in / find / create)
/// right under the scan illustration so staff see them the moment they
/// land here — same workflow as the desktop POS.
struct PosSearchPanel: View {
    @Bindable var search: PosSearchViewModel
    let hasCustomer: Bool
    let onPick: (InventoryListItem) -> Void
    let onAddCustom: () -> Void
    let onAttachWalkIn: () -> Void
    let onFindCustomer: () -> Void
    let onCreateCustomer: () -> Void

    @State private var showingScanner: Bool = false
    /// Pulses the scan-success chip when an auto-add lands. Reset on the
    /// next search edit so repeat scans each feel distinct.
    @State private var lastScannedCode: String?

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .padding(.bottom, BrandSpacing.xs)
                if let code = lastScannedCode {
                    PosScanChip(code: code)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.xs)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .accessibilityIdentifier("pos.scanChip")
                }
                resultsContent
            }
        }
        .sheet(isPresented: $showingScanner) {
            PosScanSheet { code in
                handleScanned(code)
            }
        }
    }

    /// Prominent glass-styled search field with a trailing scan button
    /// (§17.2). The scan button lives next to the field rather than inside
    /// it so the tap target stays 44pt square and doesn't fight the
    /// clear-text chevron. Staff can still type a query OR tap scan.
    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("Search items or scan", text: Binding(
                    get: { search.query },
                    set: {
                        lastScannedCode = nil
                        search.onQueryChange($0)
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pos.searchField")
                if !search.query.isEmpty {
                    Button {
                        lastScannedCode = nil
                        search.onQueryChange("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .frame(minHeight: 48)
            .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))

            Button {
                BrandHaptics.tapMedium()
                showingScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.bizarreOnOrange)
                    .frame(width: 48, height: 48)
                    .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan barcode")
            .accessibilityIdentifier("pos.scanButton")
        }
    }

    /// When a scan comes back, stuff it into the query so the row snaps
    /// into the list (`fetch()` runs via the `onQueryChange` debounce),
    /// then auto-pick the matching row if we can find one locally. The
    /// chip pulse + success haptic + dismiss already fire inside
    /// `PosScanSheet` — this side is pure glue.
    private func handleScanned(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        search.onQueryChange(trimmed)
        withAnimation(BrandMotion.barcodeSuccess) {
            lastScannedCode = trimmed
        }
        // Fast-path: if the current result set already contains a matching
        // SKU/UPC, drop it straight into the cart. Otherwise the debounced
        // search will refetch and the cashier picks from the list.
        if let match = PosScanGlue.match(code: trimmed, in: search.results) {
            BrandHaptics.success()
            onPick(match)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if search.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = search.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                Text("Couldn't load items")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button("Try again") {
                    Task { await search.load() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if search.results.isEmpty {
            // Empty state doubles as the POS home screen — feature scan +
            // customer-attach + custom-line entry points so staff have
            // somewhere to tap without scrolling through an error-looking
            // placeholder. The three customer CTAs are the headline of this
            // screen until a customer is attached (§16.4).
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    VStack(spacing: BrandSpacing.md) {
                        Image(systemName: search.query.isEmpty ? "barcode.viewfinder" : "questionmark.folder")
                            .font(.system(size: 44))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text(search.query.isEmpty ? "Scan or search to add items" : "No matches")
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        if search.query.isEmpty {
                            Text("Type a name, SKU, or barcode — or tap below to add a one-off line.")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, BrandSpacing.lg)
                        }
                    }

                    if !hasCustomer && search.query.isEmpty {
                        PosAttachCustomerActions(
                            onWalkIn: onAttachWalkIn,
                            onFind: onFindCustomer,
                            onCreate: onCreateCustomer
                        )
                        .padding(.horizontal, BrandSpacing.base)
                    }

                    Button {
                        onAddCustom()
                    } label: {
                        Label("Add a custom line", systemImage: "plus.circle.fill")
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOrange)
                            .padding(.horizontal, BrandSpacing.base)
                            .padding(.vertical, BrandSpacing.sm)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .background(Color.bizarreSurface1, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 0.5))
                    .accessibilityIdentifier("pos.addCustomLine")
                    .accessibilityLabel("Add a custom line to cart")
                }
                .padding(.top, BrandSpacing.xxl)
                .padding(.bottom, BrandSpacing.xl)
                .frame(maxWidth: .infinity)
            }
        } else {
            List(search.results) { item in
                Button {
                    BrandHaptics.success()
                    onPick(item)
                } label: {
                    PosSearchRow(item: item)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel("Add \(item.displayName) to cart")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// Tiny glass chip that pulses in under the search field after a
/// successful scan — gives staff eyes-on-the-device confirmation without
/// stealing focus from the result list.
struct PosScanChip: View {
    let code: String

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Scanned \(code)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface1.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bizarreOrange.opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanned \(code)")
    }
}

/// Trio of customer-attach CTAs that sit inside the POS empty state
/// (§16.4). Visually distinct from the single "Add a custom line" pill —
/// these get a full-width rounded tile with a leading icon and
/// `.bizarreSurface1` background so the customer-attach tier reads as the
/// headline action on the empty screen. Tokens only — no raw hex.
struct PosAttachCustomerActions: View {
    let onWalkIn: () -> Void
    let onFind: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            PosAttachCustomerButton(
                title: "Walk-in customer",
                subtitle: "Charge without a record",
                icon: "figure.walk",
                accessibilityIdentifier: "pos.attachWalkIn",
                action: onWalkIn
            )
            PosAttachCustomerButton(
                title: "Find existing customer",
                subtitle: "Search by name, phone, or email",
                icon: "magnifyingglass",
                accessibilityIdentifier: "pos.findCustomer",
                action: onFind
            )
            PosAttachCustomerButton(
                title: "Create new customer",
                subtitle: "Add a new record and attach it",
                icon: "person.crop.circle.badge.plus",
                accessibilityIdentifier: "pos.createCustomer",
                action: onCreate
            )
        }
    }
}

/// Single customer-attach tile. Leading bizarreOrange icon, body text, no
/// trailing affordance — the whole row is the tap target. Slightly more
/// prominent than the "Add custom line" pill to signal a different tier.
private struct PosAttachCustomerButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.tap()
            action()
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.bizarreOnOrange)
                    .frame(width: 40, height: 40)
                    .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(subtitle)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: BrandSpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

/// Result row in the POS picker — shows name + SKU + price. No stock
/// colour coding at scaffold level; coming in §16.2.
struct PosSearchRow: View {
    let item: InventoryListItem

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                if let sku = item.sku, !sku.isEmpty {
                    Text("SKU \(sku)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            if let cents = item.priceCents {
                Text(CartMath.formatCents(cents))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }
}
#endif
