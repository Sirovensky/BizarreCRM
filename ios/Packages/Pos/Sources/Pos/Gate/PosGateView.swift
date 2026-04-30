/// PosGateView.swift
/// Agent B — Customer Gate (Frame 1)
///
/// Adaptive layout:
///   • iPhone: NavigationStack with .searchable(placement: .navigationBarDrawer),
///     hero title "Who's this sale for?", "Search above, or:" label,
///     two side-by-side fallback buttons, ready-for-pickup strip.
///   • iPad: same content in the detail column of
///     NavigationSplitView(columnVisibility: .detailOnly), 680pt max-width
///     centred, buttons side-by-side at 72pt min-height, pickup strip below.
///     Cart column shows "No customer" placeholder.
///
/// Uses @Environment(\.horizontalSizeClass) for the adaptive split.
/// Liquid Glass on nav chrome only; buttons + rows on solid surfaceSolid.
///
/// TODO: migrate to posTheme once Agent A lands.

#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - Main view

public struct PosGateView: View {
    @State private var vm: PosGateViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.posTheme) private var theme

    // Haptic trigger counters — incremented on button tap to fire sensoryFeedback.
    @State private var createNewTapTrigger: Int = 0
    @State private var walkInTapTrigger: Int = 0

    public init(vm: PosGateViewModel) {
        self._vm = State(wrappedValue: vm)
    }

    public var body: some View {
        if hSizeClass == .compact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 14)

                    fallbackOrLabel
                        .padding(.bottom, 10)

                    fallbackButtons(minHeight: 64, horizontalPadding: 14)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    pickupStripSection(isCompact: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("POS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("POS")
                            .font(.headline)
                            .foregroundStyle(Color.bizarreOnSurface)
                        Text("Register open · Pavel I.")
                            .font(.caption2)
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        onlineChip
                        Button {
                            // TODO: overflow menu (settings, end register session)
                        } label: {
                            Text("⋯")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.bizarreOnSurface)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More options")
                    }
                }
            }
            .searchable(
                text: $vm.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by name, phone, ticket, or loyalty #"
            )
            .overlay(alignment: .top) {
                if vm.isSearching {
                    searchResultsOverlay
                } else if !vm.results.isEmpty {
                    searchResultsOverlay
                }
            }
            .sheet(isPresented: $vm.isShowingPickupSheet) {
                PickupListSheet(
                    isPresented: $vm.isShowingPickupSheet,
                    allPickups: vm.pickupTickets,
                    onSelect: { vm.openPickup(id: $0) }
                )
            }
        }
        .task { await vm.loadPickups() }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: createNewTapTrigger)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: walkInTapTrigger)
    }

    // MARK: - iPad layout
    //
    // Wrapped in `PosRegisterLayout` so the gate phase shares the exact
    // same `rail | catalog | cart` template as path-choice and the active
    // register: 60pt topbar, catalog on the left at `catalogFraction:0.65`,
    // 420pt cart on the right. Earlier the gate used a `NavigationStack`
    // with `.searchable` which added ~96pt of nav-bar + drawer chrome
    // above the cart column — the customer placeholder landed ~30pt
    // lower than the post-gate "Walk-in" header. That broke the
    // smooth-river feel; using the same template fixes the y-origin.
    private var iPadLayout: some View {
        PosRegisterLayout(
            catalogFraction: 0.65
        ) {
            iPadGateTopbar
        } catalog: {
            ZStack(alignment: .top) {
                itemsColumn
                if vm.isSearching || !vm.results.isEmpty {
                    searchResultsOverlay
                        .frame(maxWidth: 680)
                        .padding(.horizontal, 32)
                        .padding(.top, 64) // sits below the inline search field
                }
            }
        } cart: {
            cartPlaceholderColumn
        }
        .sheet(isPresented: $vm.isShowingPickupSheet) {
            PickupListSheet(
                isPresented: $vm.isShowingPickupSheet,
                allPickups: vm.pickupTickets,
                onSelect: { vm.openPickup(id: $0) }
            )
        }
        .task { await vm.loadPickups() }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: createNewTapTrigger)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: walkInTapTrigger)
    }

    // MARK: - iPad gate · topbar (centered title + trailing online chip + ⋯)

    private var iPadGateTopbar: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("POS · new sale")
                    .font(.headline)
                    .foregroundStyle(Color.bizarreOnSurface)
                Text("Register open · Pavel I.")
                    .font(.caption2)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Spacer()
                onlineChip
                Button {
                    // TODO: overflow menu (settings, end register session)
                } label: {
                    Text("⋯")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.bizarreOnSurface)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, BrandSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - iPad gate · items column (search + hero + buttons + pickup strip)

    private var itemsColumn: some View {
        ScrollView {
            VStack(spacing: 0) {
                inlineSearchField
                    .frame(maxWidth: 680)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                heroHeader
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                fallbackOrLabel
                    .padding(.bottom, 10)

                fallbackButtons(minHeight: 72, cornerRadius: 18, horizontalPadding: 20)
                    .frame(maxWidth: 680)
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                pickupStripSection(isCompact: false)
                    .frame(maxWidth: 680)
                    .padding(.top, 36)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Inline search field (replaces `.searchable` nav-bar drawer)

    private var inlineSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField(
                "Search by name, phone, email, loyalty #, or scan customer card",
                text: $vm.query
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.bizarreOnSurface)
            .submitLabel(.search)
            .accessibilityIdentifier("pos.gate.search")
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bizarreSurface1.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - iPad gate · cart placeholder column ("No customer")

    private var cartPlaceholderColumn: some View {
        VStack(spacing: 0) {
            // Cart head — empty-customer state. Padding mirrors
            // `PosIPadCartPanel.cartCustomerHeader` exactly so the "No
            // customer" header lands at the same y-origin as the post-gate
            // "Walk-in" / customer-attached header (cashier never sees the
            // header jump when the gate clears).
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.bizarreOnSurface.opacity(0.06))
                        .overlay(Circle().strokeBorder(Color.bizarreOnSurface.opacity(0.18),
                                                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No customer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.bizarreOnSurface)
                    Text("Pick a customer to start the sale.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(.bizarreOutline)

            // Empty body — caption per mockup, no pointing-emoji (the cart
            // panel sits on the right of the items column so a left-pointing
            // emoji would aim at the cart itself, not the customer chooser).
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "cart")
                    .font(.system(size: 40))
                    .opacity(0.25)
                    .foregroundStyle(Color.bizarreOnSurface)
                    .accessibilityHidden(true)
                Text("Every sale needs a customer attached.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.xl)

            Spacer(minLength: 0)

            // Totals stub — all $0.00
            VStack(spacing: BrandSpacing.xs) {
                totalsRow(label: "Subtotal", value: "$0.00")
                totalsRow(label: "Tax", value: "$0.00")
                Divider().overlay(Color.bizarreOutline.opacity(0.2))
                HStack {
                    Text("Total")
                        .font(.brandLabelLarge())
                        .foregroundStyle(Color.bizarreOnSurface)
                    Spacer()
                    Text("$0.00")
                        .font(.brandTitleLarge())
                        .foregroundStyle(Color.bizarreOnSurface)
                        .monospacedDigit()
                }
            }
            .padding(BrandSpacing.md)

            // Disabled "Attach customer first" CTA — slimmed to match the
            // post-gate Charge button height for vertical-rhythm parity.
            Text("Attach customer first")
                .font(.brandTitleSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.vertical, 8)
                .background(Color.bizarreOnSurface.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
        }
        // Background + leading edge divider are supplied by `PosRegisterLayout`'s
        // glass-backed cart column wrapper — explicit `Color.bizarreSurface1`
        // here would render glass-on-solid and break the column's brand glass.
    }

    private func totalsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurface)
                .monospacedDigit()
        }
    }

    // MARK: - iPad gate · topbar principal title

    @ToolbarContentBuilder
    private var gateTopbarPrincipal: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text("POS · new sale")
                    .font(.headline)
                    .foregroundStyle(Color.bizarreOnSurface)
                Text("Register open · Pavel I.")
                    .font(.caption2)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Shared sub-views

    /// "Who's this for?" hero title block (matches mockup Frame 1 wording exactly).
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Who's this for?")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.33)   // letter-spacing: -0.015em @ 22pt
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(Color.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text("Every sale starts with a customer.")
                .font(.system(size: 13))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    /// "Search above, or:" label.
    private var fallbackOrLabel: some View {
        Text("Search above, or:")
            .font(.caption)
            .foregroundStyle(theme.muted2)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Two side-by-side fallback buttons.
    /// - Parameters:
    ///   - minHeight: Minimum row height (64 iPhone, 72 iPad per mockup).
    ///   - cornerRadius: Card corner radius (16 iPhone, 18 iPad per mockup).
    ///   - horizontalPadding: Inner horizontal padding (14 iPhone, 20 iPad per mockup).
    private func fallbackButtons(
        minHeight: CGFloat,
        cornerRadius: CGFloat = 16,
        horizontalPadding: CGFloat = 14
    ) -> some View {
        HStack(spacing: 10) {
            // Create new customer
            Button {
                createNewTapTrigger += 1
                vm.selectCreateNew()
            } label: {
                Text("＋ Create new customer")
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .frame(maxWidth: .infinity, minHeight: minHeight)
                    .padding(.horizontal, horizontalPadding)
                    .foregroundStyle(Color.bizarreOnSurface)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.bizarreOnSurface.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .stroke(Color.bizarreOnSurface.opacity(0.14), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create new customer")
            .accessibilityHint("Opens the create customer form")

            // Walk-in
            Button {
                walkInTapTrigger += 1
                vm.selectWalkIn()
            } label: {
                Text("🚶 Walk-in · no record")
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .frame(maxWidth: .infinity, minHeight: minHeight)
                    .padding(.horizontal, horizontalPadding)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.bizarreOnSurface.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .strokeBorder(
                                        Color.bizarreOnSurface.opacity(0.20),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Walk-in, no customer record")
            .accessibilityHint("Start a sale without attaching a customer")
        }
    }

    /// Ready-for-pickup strip: section header + 2 rows + "View all →" button.
    ///
    /// - Parameter isCompact: When true uses "Recent Ready for pickup" header copy
    ///   (iPhone); when false uses the shorter "Ready for pickup" (iPad).
    @ViewBuilder
    private func pickupStripSection(isCompact: Bool) -> some View {
        if !vm.pickupTickets.isEmpty {
            let headerText = isCompact
                ? "Recent Ready for pickup · \(vm.totalPickupCount)"
                : "Ready for pickup · \(vm.totalPickupCount)"
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(headerText)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(theme.muted2)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button {
                        vm.showAllPickups()
                    } label: {
                        Text("View all →")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(Color.bizarreTeal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all ready-for-pickup tickets")
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 10)

                VStack(spacing: 8) {
                    ForEach(Array(vm.pickupTickets.enumerated()), id: \.element.id) { index, pickup in
                        PickupRow(
                            pickup: pickup,
                            isFirst: index == 0,
                            badgeSize: isCompact ? 32 : 36,
                            badgeCornerRadius: isCompact ? 9 : 10,
                            badgeFontSize: isCompact ? 15 : 18
                        ) {
                            vm.openPickup(id: pickup.id)
                        }
                    }
                }
            }
        }
    }

    /// Search results list overlay (shown beneath the nav bar when results exist).
    @ViewBuilder
    private var searchResultsOverlay: some View {
        VStack(spacing: 0) {
            if vm.isSearching {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.bizarreSurface1)
            } else if let error = vm.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.bizarreError)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Color.bizarreOnSurface)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.bizarreSurface1)
            } else if !vm.results.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(vm.results) { hit in
                        CustomerHitRow(hit: hit) {
                            vm.selectExistingCustomer(id: hit.id)
                        }
                        Divider()
                            .overlay(Color.bizarreOutline)
                    }
                }
                .background(Color.bizarreSurface1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var onlineChip: some View {
        Label("Online", systemImage: "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.bizarreSuccess)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("Register online")
    }
}

// MARK: - Customer hit row (inline search result)

private struct CustomerHitRow: View {
    let hit: CustomerSearchHit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Initials avatar — neutral surface tile to keep the
                // customer chrome out of the brand accent palette.
                ZStack {
                    Circle()
                        .fill(Color.bizarreOnSurface.opacity(0.06))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.bizarreOnSurface.opacity(0.18), lineWidth: 1)
                        )
                        .frame(width: 40, height: 40)
                    Text(hit.initials)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .lineLimit(1)
                    if let contact = hit.contactLine {
                        Text(contact)
                            .font(.caption)
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hit.displayName)\(hit.contactLine.map { ", \($0)" } ?? "")")
        .accessibilityHint("Select this customer")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("iPhone — empty state") {
    let vm = PosGateViewModel(
        customerRepo: PreviewCustomerRepository(),
        ticketsRepo: PreviewGateTicketsRepository()
    )
    PosGateView(vm: vm)
        .environment(\.horizontalSizeClass, .compact)
        .preferredColorScheme(.dark)
}

#Preview("iPhone — with pickups") {
    let vm = PosGateViewModel(
        customerRepo: PreviewCustomerRepository(),
        ticketsRepo: PreviewGateTicketsRepository(pickups: [
            ReadyPickup(id: 1, orderId: "4829", customerName: "Sarah M.", deviceSummary: "iPhone 14 screen", totalCents: 27400),
            ReadyPickup(id: 2, orderId: "4831", customerName: "Marco D.", deviceSummary: "Samsung S23 battery", totalCents: 14200),
        ])
    )
    PosGateView(vm: vm)
        .environment(\.horizontalSizeClass, .compact)
        .preferredColorScheme(.dark)
}
#endif
#endif
