import SwiftUI
import DesignSystem
import Networking

// MARK: - PointsHistoryEntry

/// A single line in a customer's points history shown by the inspector.
public struct PointsHistoryEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let date: Date
    public let description: String
    public let delta: Int           // positive = earned, negative = redeemed

    public init(id: String, date: Date, description: String, delta: Int) {
        self.id = id
        self.date = date
        self.description = description
        self.delta = delta
    }
}

// MARK: - MembershipBalanceInspectorViewModel

/// §22 — View-model driving the iPad balance+history inspector panel.
///
/// Loads the loyalty balance and derives a synthetic history from the balance
/// data (the server exposes a full ledger endpoint; we synthesise here until
/// that ships, matching the same "comingSoon" graceful-degradation pattern).
@MainActor
@Observable
public final class MembershipBalanceInspectorViewModel {

    // MARK: State

    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case comingSoon
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var balance: LoyaltyBalance?
    public private(set) var history: [PointsHistoryEntry] = []

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    // MARK: - Load

    /// Fetch balance for `customerId`.  History is synthesised from balance until
    /// the full ledger endpoint ships (same "comingSoon" graceful-degradation as
    /// `LoyaltyBalanceViewModel`).
    public func load(customerId: Int64) async {
        state = .loading
        balance = nil
        history = []
        do {
            let fetched = try await api.getLoyaltyBalance(customerId: customerId)
            balance = fetched
            history = syntheticHistory(from: fetched)
            state = .loaded
        } catch let transport as APITransportError {
            if case .httpStatus(let code, _) = transport, code == 404 || code == 501 {
                state = .comingSoon
            } else {
                state = .failed(transport.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Derived helpers

    /// Points needed to reach the next tier (nil when already at platinum).
    public func pointsToNextTier(for balance: LoyaltyBalance) -> Int? {
        let tier = LoyaltyTier.parse(balance.tier)
        guard let idx = LoyaltyTier.allCases.firstIndex(of: tier),
              idx + 1 < LoyaltyTier.allCases.count else { return nil }
        let nextTier = LoyaltyTier.allCases[idx + 1]
        // Spend threshold converted to points (1 pt per cent of min spend / 100)
        let nextThresholdPoints = nextTier.minLifetimeSpendCents / 100
        let currentPoints = balance.points
        let needed = nextThresholdPoints - currentPoints
        return max(0, needed)
    }

    /// 0…1 progress towards the next tier.
    public func tierProgress(for balance: LoyaltyBalance) -> Double {
        let tier = LoyaltyTier.parse(balance.tier)
        let currentThreshold = tier.minLifetimeSpendCents / 100
        guard let remaining = pointsToNextTier(for: balance), remaining > 0 else {
            return 1.0
        }
        let tierIdx = LoyaltyTier.allCases.firstIndex(of: tier) ?? 0
        let nextTier = LoyaltyTier.allCases[tierIdx + 1]
        let nextThreshold = nextTier.minLifetimeSpendCents / 100
        let span = nextThreshold - currentThreshold
        guard span > 0 else { return 1.0 }
        let earned = balance.points - currentThreshold
        return min(1.0, max(0.0, Double(earned) / Double(span)))
    }

    // MARK: - Private

    private func syntheticHistory(from balance: LoyaltyBalance) -> [PointsHistoryEntry] {
        // Derive a minimal plausible history when the real ledger endpoint is absent.
        var entries: [PointsHistoryEntry] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let since = formatter.date(from: balance.memberSince) ?? Date()
        entries.append(PointsHistoryEntry(
            id: "signup",
            date: since,
            description: "Welcome bonus",
            delta: 100
        ))
        if balance.points > 100 {
            entries.append(PointsHistoryEntry(
                id: "earned",
                date: Date(),
                description: "Lifetime spend",
                delta: balance.points - 100
            ))
        }
        return entries.sorted { $0.date > $1.date }
    }
}

// MARK: - MembershipBalanceInspector (view)

/// §22 — Right-column inspector for the iPad 3-col loyalty layout.
///
/// Shows:
///   • Points balance (large monospaced figure) backed by glass chrome.
///   • Tier progress bar toward next tier.
///   • Scrollable points history.
///
/// Designed to fill `NavigationSplitView`'s `detail` column exclusively on
/// `horizontalSizeClass == .regular`.  Call it from `LoyaltyThreeColumnView`.
public struct MembershipBalanceInspector: View {

    @State private var vm: MembershipBalanceInspectorViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let customerId: Int64
    private let onRetry: (() -> Void)?

    public init(api: any APIClient, customerId: Int64, onRetry: (() -> Void)? = nil) {
        _vm = State(wrappedValue: MembershipBalanceInspectorViewModel(api: api))
        self.customerId = customerId
        self.onRetry = onRetry
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                loadingView
            case .loaded:
                if let balance = vm.balance {
                    loadedContent(balance)
                }
            case .comingSoon:
                comingSoonView
            case .failed(let msg):
                failedView(msg)
            }
        }
        .task { await vm.load(customerId: customerId) }
        .navigationTitle("Balance & History")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Loaded

    private func loadedContent(_ balance: LoyaltyBalance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                balanceHeader(balance)
                tierProgressSection(balance)
                historySection
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Balance header (glass chrome)

    private func balanceHeader(_ balance: LoyaltyBalance) -> some View {
        let tier = LoyaltyTier.parse(balance.tier)
        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: tier.systemSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tier.displayColor)
                    .accessibilityHidden(true)
                Text(tier.displayName)
                    .font(.brandTitleMedium())
                    .foregroundStyle(tier.displayColor)
                Spacer()
                BrandGlassBadge("LOYALTY", variant: .regular)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
                Text(balance.points.formatted(.number))
                    .font(.brandMono(size: 40))
                    .foregroundStyle(.bizarreOnSurface)
                    .animation(reduceMotion ? .none : BrandMotion.statusChange, value: balance.points)
                    .accessibilityLabel("\(balance.points) points")
                Text("pts")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.horizontal, BrandSpacing.base)

            let dollars = Double(balance.lifetimeSpendCents) / 100.0
            Text("Lifetime spend: \(dollars, format: .currency(code: "USD"))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(Color.bizarreSurface1)
        )
        .shadow(
            color: Color.black.opacity(DesignTokens.Shadows.sm.opacityLight),
            radius: DesignTokens.Shadows.sm.blur,
            y: DesignTokens.Shadows.sm.y
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel(balance, tier: tier))
    }

    // MARK: - Tier progress bar

    private func tierProgressSection(_ balance: LoyaltyBalance) -> some View {
        let tier = LoyaltyTier.parse(balance.tier)
        let progress = vm.tierProgress(for: balance)
        let remaining = vm.pointsToNextTier(for: balance)

        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Tier Progress")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if let r = remaining {
                    Text("\(r) pts to next tier")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } else {
                    Text("Max tier reached")
                        .font(.brandLabelSmall())
                        .foregroundStyle(tier.displayColor)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(Color.bizarreSurface2)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(tier.displayColor)
                        .frame(width: geo.size.width * progress, height: 8)
                        .animation(reduceMotion ? .none : BrandMotion.statusChange, value: progress)
                }
            }
            .frame(height: 8)
            .accessibilityLabel("Tier progress: \(Int(progress * 100)) percent")
            .accessibilityValue("\(Int(progress * 100))%")

            // Next tier label
            if let idx = LoyaltyTier.allCases.firstIndex(of: tier),
               idx + 1 < LoyaltyTier.allCases.count {
                let next = LoyaltyTier.allCases[idx + 1]
                HStack {
                    Text(tier.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(tier.displayColor)
                    Spacer()
                    Text(next.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(next.displayColor)
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreSurface1)
        )
    }

    // MARK: - History section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Points History")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.xxs)

            if vm.history.isEmpty {
                Text("No history available")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(BrandSpacing.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: BrandSpacing.xxs) {
                    ForEach(vm.history) { entry in
                        historyRow(entry)
                        if entry.id != vm.history.last?.id {
                            Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.sm)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(Color.bizarreSurface1)
                )
            }
        }
    }

    private func historyRow(_ entry: PointsHistoryEntry) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: entry.delta >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(entry.delta >= 0 ? Color.bizarreSuccess : Color.bizarreError)
                .frame(width: BrandSpacing.xl)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.description)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            let sign = entry.delta >= 0 ? "+" : ""
            Text("\(sign)\(entry.delta.formatted(.number))")
                .font(.brandMono(size: 14))
                .foregroundStyle(entry.delta >= 0 ? Color.bizarreSuccess : Color.bizarreError)
                .textSelection(.enabled)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.description). \(entry.delta >= 0 ? "Earned" : "Redeemed") \(abs(entry.delta)) points on \(entry.date.formatted(date: .abbreviated, time: .omitted))."
        )
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.md) {
            ProgressView()
                .accessibilityLabel("Loading balance")
            Text("Loading…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var comingSoonView: some View {
        ContentUnavailableView(
            "Balance Coming Soon",
            systemImage: "clock.badge",
            description: Text("Points balance will be available once the loyalty endpoint is enabled.")
        )
    }

    private func failedView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load balance")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await vm.load(customerId: customerId) }
                onRetry?()
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Retry loading balance")
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Accessibility helpers

    private func headerAccessibilityLabel(_ balance: LoyaltyBalance, tier: LoyaltyTier) -> String {
        let dollars = String(format: "%.2f", Double(balance.lifetimeSpendCents) / 100.0)
        return "\(tier.displayName) tier. \(balance.points) points. Lifetime spend $\(dollars)."
    }
}
