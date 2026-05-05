/// PosEntryView.swift — §16.21
///
/// POS entry screen (redesign wave, 2026-04-24).
///
/// iPhone layout:
///   • Three large entry-point tiles (Retail sale / Repair ticket / Store credit).
///   • `PosSearchBar` pinned at the bottom of the safe area (thumb zone) in idle state.
///   • On search expand: bar rises to top in 220 ms spring; tiles fade out.
///   • Unified customer + ticket search results list.
///   • "Ready for pickup" contextual banner.
///   • Recent entry quick-pick row.
///
/// iPad: continues to use `PosView.regularLayout` HStack — this view is
/// iPhone-only idle/entry state. Gate on `Platform.isCompact`.
///
/// Reduce Motion: skip spring, use fade only.
/// Reduce Transparency: opaque `surface` fill replaces `.brandGlass`.
/// Glass budget: 1 (expanded search bar only).

#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - PosEntryView

public struct PosEntryView: View {

    @Bindable var vm: PosEntryViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.posTheme) private var theme

    // MARK: - Entry-point tile actions

    public var onRetailSale: () -> Void
    public var onRepairTicket: () -> Void
    public var onStoreCredit: () -> Void

    public init(
        vm: PosEntryViewModel,
        onRetailSale: @escaping () -> Void = {},
        onRepairTicket: @escaping () -> Void = {},
        onStoreCredit: @escaping () -> Void = {}
    ) {
        self.vm = vm
        self.onRetailSale = onRetailSale
        self.onRepairTicket = onRepairTicket
        self.onStoreCredit = onStoreCredit
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            // Main content: tiles (fades out when search expanded)
            idleContent
                .opacity(vm.isSearchExpanded ? 0 : 1)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.1)
                        : .easeOut(duration: DesignTokens.Motion.snappy),
                    value: vm.isSearchExpanded
                )
                .allowsHitTesting(!vm.isSearchExpanded)

            // Search results overlay (fades in when expanded)
            if vm.isSearchExpanded {
                searchContent
                    .transition(.opacity)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.1)
                            : .easeOut(duration: DesignTokens.Motion.snappy),
                        value: vm.isSearchExpanded
                    )
            }

            // PosSearchBar — pinned at bottom (idle) or top (expanded)
            VStack {
                if vm.isSearchExpanded {
                    PosSearchBar(vm: vm, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                    Spacer()
                } else {
                    Spacer()
                    PosSearchBar(vm: vm, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.lg)
                }
            }
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.12)
                    : .spring(duration: DesignTokens.Motion.snappy, bounce: 0.15),
                value: vm.isSearchExpanded
            )
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Idle content (three tiles)

    private var idleContent: some View {
        VStack(spacing: 0) {
            // Ready-for-pickup banner (customer-specific)
            if vm.readyForPickupCount > 0 {
                readyForPickupBanner
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.md)
            }

            Spacer()

            VStack(spacing: BrandSpacing.sm) {
                entryTile(
                    icon: "cart.fill",
                    title: "Retail sale",
                    subtitle: "Start a new cart",
                    isPrimary: true,
                    action: onRetailSale
                )
                entryTile(
                    icon: "wrench.and.screwdriver.fill",
                    title: "Create repair ticket",
                    subtitle: "Check in a device",
                    isPrimary: false,
                    action: onRepairTicket
                )
                entryTile(
                    icon: "creditcard.fill",
                    title: "Store credit / payment",
                    subtitle: "Issue or redeem credit",
                    isPrimary: false,
                    action: onStoreCredit
                )
            }
            .padding(.horizontal, BrandSpacing.base)

            // Recent entries quick-pick
            if !vm.recentEntries.isEmpty {
                recentEntriesRow
                    .padding(.top, BrandSpacing.lg)
            }

            Spacer()
            // Bottom spacer for PosSearchBar (≈72pt)
            Spacer().frame(height: 72 + BrandSpacing.lg)
        }
    }

    // MARK: - Entry-point tile

    private func entryTile(
        icon: String,
        title: String,
        subtitle: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            BrandHaptics.tapMedium()
            action()
        }) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isPrimary ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                    .frame(width: 44, height: 44)
                    .background(isPrimary ? Color.bizarreOrange.opacity(0.15) : Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.brandTitleMedium())
                        .foregroundStyle(Color.bizarreOnSurface)
                    Text(subtitle)
                        .font(.brandBodyMedium())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .padding(.horizontal, BrandSpacing.md)
            .frame(minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                            .strokeBorder(
                                isPrimary ? Color.bizarreOrange.opacity(0.4) : Color.bizarreOutline.opacity(0.4),
                                lineWidth: isPrimary ? 1 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: - Ready for pickup banner

    private var readyForPickupBanner: some View {
        HStack {
            Circle()
                .fill(Color.bizarreSuccess)
                .frame(width: 8, height: 8)
            Text("\(vm.readyForPickupCount) ticket\(vm.readyForPickupCount == 1 ? "" : "s") ready for pickup")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreSuccess)
            Spacer()
            Text("Open cart →")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.bizarreSuccess)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xs)
                .background(Color.bizarreSuccess.opacity(0.12), in: Capsule())
        }
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreSuccess.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(Color.bizarreSuccess.opacity(0.25), lineWidth: 0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.readyForPickupCount) tickets ready for pickup. Open cart.")
    }

    // MARK: - Recent entries row

    private var recentEntriesRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("RECENT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .tracking(1)
                .padding(.horizontal, BrandSpacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(vm.recentEntries) { entry in
                        Button {
                            BrandHaptics.tap()
                            switch entry.kind {
                            case .customer(let id, let name):
                                vm.attachCustomer(CustomerSearchHit(
                                    id: id,
                                    displayName: name,
                                    contactLine: nil,
                                    initials: String(name.prefix(2)).uppercased()
                                ))
                            case .ticket(_, _):
                                break // open ticket navigation handled by parent
                            case .walkIn:
                                vm.walkIn()
                            }
                        } label: {
                            Text(entry.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.bizarreOnSurface)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(Color.bizarreSurface2, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recent: \(entry.label)")
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    // MARK: - Search content (expanded)

    private var searchContent: some View {
        VStack(spacing: 0) {
            // Spacer for the search bar at top
            Spacer().frame(height: 64 + BrandSpacing.base)

            if vm.isLoading {
                loadingSkeleton
            } else if let err = vm.errorMessage {
                errorState(message: err)
            } else if vm.query.isEmpty {
                emptyQueryState
            } else if vm.searchResults.isEmpty {
                noResultsState
            } else {
                resultsList
            }
        }
    }

    // MARK: - Results list

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.searchResults) { result in
                    switch result {
                    case .customer(let hit):
                        customerRow(hit)
                            .padding(.horizontal, BrandSpacing.base)
                            .padding(.vertical, BrandSpacing.sm)
                        Divider().padding(.horizontal, BrandSpacing.lg)

                    case .ticket(let hit):
                        ticketRow(hit)
                            .padding(.horizontal, BrandSpacing.base)
                            .padding(.vertical, BrandSpacing.sm)
                        Divider().padding(.horizontal, BrandSpacing.lg)
                    }
                }
            }
        }
        .accessibilityLabel("\(vm.searchResults.count) search results")
    }

    private func customerRow(_ hit: CustomerSearchHit) -> some View {
        Button {
            vm.attachCustomer(hit)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                // Initials avatar
                Text(hit.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.bizarreOnSurface)
                    .frame(width: 40, height: 40)
                    .background(Color.bizarreOrange.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.displayName)
                        .font(.brandTitleMedium())
                        .foregroundStyle(Color.bizarreOnSurface)
                    if let contact = hit.contactLine {
                        Text(contact)
                            .font(.brandBodyMedium())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                Image(systemName: "person.fill.badge.plus")
                    .foregroundStyle(Color.bizarreOrange)
                    .font(.system(size: 16))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Customer: \(hit.displayName). Double-tap to attach.")
    }

    private func ticketRow(_ hit: TicketSearchHit) -> some View {
        Button {
            vm.openTicket(hit)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.bizarreTeal)
                    .frame(width: 40, height: 40)
                    .background(Color.bizarreTeal.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(hit.orderId) · \(hit.summary)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(Color.bizarreOnSurface)
                        .lineLimit(1)
                    HStack(spacing: BrandSpacing.xs) {
                        if hit.isReadyForPickup {
                            Text("Ready for pickup")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.bizarreSuccess)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.bizarreSuccess.opacity(0.12), in: Capsule())
                        } else {
                            Text(hit.status)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        }
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ticket \(hit.orderId) \(hit.summary) status \(hit.status)")
    }

    // MARK: - States

    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: BrandSpacing.md) {
                    Circle()
                        .fill(Color.bizarreSurface2)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreSurface2)
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreSurface2)
                            .frame(width: 100, height: 12)
                    }
                    Spacer()
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .redacted(reason: .placeholder)
            }
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.bizarreError)
            Text("Search unavailable · check connection")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { vm.scheduleSearch() }
                .buttonStyle(.borderedProminent)
                .tint(Color.bizarreOrange)
        }
        .padding(BrandSpacing.xl)
    }

    private var emptyQueryState: some View {
        VStack(spacing: BrandSpacing.sm) {
            if !vm.recentEntries.isEmpty {
                recentEntriesRow
            } else {
                Text("Search for a customer, part, or ticket")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }
        }
        .padding(.top, BrandSpacing.xl)
    }

    private var noResultsState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 36))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Text("No customers or tickets match")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
            HStack(spacing: BrandSpacing.md) {
                Button("Create new customer") { vm.onCreateCustomer?() }
                    .buttonStyle(.bordered)
                Button("Walk-in") { vm.walkIn() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.bizarreOrange)
            }
        }
        .padding(BrandSpacing.xl)
    }
}

// MARK: - PosSearchBar (§16.21)

/// Animated search bar component.
///
/// Idle: plain `surface-2` fill, pinned at bottom. No glass.
/// Expanded: `.brandGlass` background (chrome role). Counts as 1 toward GlassBudget.
/// Transition: 220 ms spring (bottom → top) or instant fade (Reduce Motion).
struct PosSearchBar: View {
    @Bindable var vm: PosEntryViewModel
    let reduceMotion: Bool
    let reduceTransparency: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            TextField("Search customer, part, or ticket", text: $vm.query)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pos.entry.searchField")
                .accessibilityLabel("Search customer, part, or ticket")
                .onChange(of: isFocused) { _, focused in
                    if focused && !vm.isSearchExpanded {
                        vm.expandSearch()
                    }
                }

            if vm.isSearchExpanded {
                if vm.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !vm.query.isEmpty {
                    Button {
                        vm.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }

                Button("Cancel") {
                    isFocused = false
                    vm.collapseSearch()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityLabel("Cancel search")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                // Camera/barcode scan shortcut
                Button {
                    BrandHaptics.tap()
                    // Delegate to parent PosSearchPanel scan sheet
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .foregroundStyle(Color.bizarreOrange)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan barcode or QR code")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .frame(minHeight: 50)
        .background {
            if vm.isSearchExpanded && !reduceTransparency {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(Color.bizarreOrange.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bizarreSurface2.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.snappy),
            value: vm.isSearchExpanded
        )
    }
}
#endif
