#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - LTVTierEditorView

/// §44.2 — Admin view for customizing LTV tier thresholds + perks per tier.
///
/// Saves changes via `PATCH /tenant/ltv-policy`.
///
/// iPhone: scrollable form.
/// iPad: two-column NavigationSplitView (tier list sidebar + detail editor).
public struct LTVTierEditorView: View {
    @State private var vm: LTVTierEditorViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: LTVTierEditorViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .navigationTitle("LTV Policy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .toolbar { saveToolbar }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationSplitView {
            tierList
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .toolbar { saveToolbar }
        }
    }

    // MARK: Shared components

    @ViewBuilder
    private var tierList: some View {
        List(LTVTier.allCases, id: \.self, selection: $vm.selectedTier) { tier in
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: tier.icon)
                    .foregroundStyle(tier.color)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(tier.label)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Text(thresholdDescription(tier))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .hoverEffect(.highlight)
        }
        .listStyle(.sidebar)
        .navigationTitle("LTV Tiers")
    }

    @ViewBuilder
    private var form: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                thresholdsSection
                perksSection
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var thresholdsSection: some View {
        Section("Thresholds") {
            HStack {
                Text("Silver from")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                TextField("$500", text: $vm.silverDollarsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.brandMono(size: 14))
                    .frame(width: 90)
            }
            HStack {
                Text("Gold from")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                TextField("$1 500", text: $vm.goldDollarsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.brandMono(size: 14))
                    .frame(width: 90)
            }
            HStack {
                Text("Platinum from")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                TextField("$5 000", text: $vm.platinumDollarsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.brandMono(size: 14))
                    .frame(width: 90)
            }
        }
    }

    @ViewBuilder
    private var perksSection: some View {
        Section("Perks for \(vm.selectedTier?.label ?? "tier")") {
            if let tier = vm.selectedTier {
                let perks = vm.perks(for: tier)
                if perks.isEmpty {
                    Text("No perks configured.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                ForEach(perks) { perk in
                    HStack {
                        Text(perk.description)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        perkKindLabel(perk.kind)
                    }
                }
                Button {
                    vm.addPerk(for: tier)
                } label: {
                    Label("Add perk", systemImage: "plus.circle")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add perk for \(tier.label) tier")
            }
        }
    }

    private func perkKindLabel(_ kind: LTVPerkKind) -> some View {
        let text: String
        switch kind {
        case .discount(let pct):       text = "\(pct)% off"
        case .priorityQueue(let pos):  text = "Queue #\(pos)"
        case .warrantyMonths(let m):   text = "+\(m) mo warranty"
        case .custom(let s):           text = s
        }
        return Text(text)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
    }

    private var saveToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.save() }
            } label: {
                if vm.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOrange)
                }
            }
            .disabled(vm.isSaving)
            .keyboardShortcut("S", modifiers: .command)
            .accessibilityLabel("Save LTV policy")
        }
    }

    private func thresholdDescription(_ tier: LTVTier) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        func fmt(_ c: Int) -> String { f.string(from: NSNumber(value: c / 100)) ?? "$\(c / 100)" }
        switch tier {
        case .bronze:   return "< \(fmt(vm.thresholds.silverCents))"
        case .silver:   return "\(fmt(vm.thresholds.silverCents))–\(fmt(vm.thresholds.goldCents))"
        case .gold:     return "\(fmt(vm.thresholds.goldCents))–\(fmt(vm.thresholds.platinumCents))"
        case .platinum: return "> \(fmt(vm.thresholds.platinumCents))"
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class LTVTierEditorViewModel {
    var thresholds: LTVThresholds = .default
    var allPerks: [LTVPerk] = LTVPerk.defaults
    var selectedTier: LTVTier? = .silver
    var isLoading = false
    var isSaving = false
    var errorMessage: String?

    // Threshold text fields (dollars, no decimals)
    var silverDollarsText   = "500"
    var goldDollarsText     = "1500"
    var platinumDollarsText = "5000"

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Try to fetch tenant-specific thresholds; fall back silently.
        if let policy: LTVPolicy = try? await api.get("/api/v1/tenant/ltv-policy", as: LTVPolicy.self) {
            let t = LTVThresholds(
                silverCents:   policy.silverCents,
                goldCents:     policy.goldCents,
                platinumCents: policy.platinumCents
            )
            thresholds = t
            allPerks   = policy.perks ?? LTVPerk.defaults
        }
        syncTextFields()
    }

    func save() async {
        guard let thresholdsFromText = parsedThresholds() else {
            errorMessage = "Invalid threshold values. Enter whole dollar amounts."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let body = LTVPolicyPatch(
            silverCents:   thresholdsFromText.silverCents,
            goldCents:     thresholdsFromText.goldCents,
            platinumCents: thresholdsFromText.platinumCents,
            perks:         allPerks
        )
        do {
            let updated: LTVPolicy = try await api.patch("/api/v1/tenant/ltv-policy", body: body, as: LTVPolicy.self)
            thresholds = LTVThresholds(
                silverCents:   updated.silverCents,
                goldCents:     updated.goldCents,
                platinumCents: updated.platinumCents
            )
            allPerks = updated.perks ?? allPerks
            syncTextFields()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func perks(for tier: LTVTier) -> [LTVPerk] {
        LTVPerkApplier.applicablePerks(tier: tier, perks: allPerks)
    }

    func addPerk(for tier: LTVTier) {
        let newPerk = LTVPerk(
            id: UUID().uuidString,
            tier: tier,
            kind: .discount(percent: 5),
            description: "New perk"
        )
        allPerks = allPerks + [newPerk]
    }

    func clearError() { errorMessage = nil }

    // MARK: Private

    private func syncTextFields() {
        silverDollarsText   = String(thresholds.silverCents   / 100)
        goldDollarsText     = String(thresholds.goldCents     / 100)
        platinumDollarsText = String(thresholds.platinumCents / 100)
    }

    private func parsedThresholds() -> LTVThresholds? {
        guard
            let s = Int(silverDollarsText.filter(\.isNumber)),
            let g = Int(goldDollarsText.filter(\.isNumber)),
            let p = Int(platinumDollarsText.filter(\.isNumber)),
            s > 0, g > s, p > g
        else { return nil }
        return LTVThresholds(silverCents: s * 100, goldCents: g * 100, platinumCents: p * 100)
    }
}

// MARK: - API models

private struct LTVPolicy: Codable, Sendable {
    let silverCents:   Int
    let goldCents:     Int
    let platinumCents: Int
    let perks:         [LTVPerk]?

    enum CodingKeys: String, CodingKey {
        case silverCents   = "silver_cents"
        case goldCents     = "gold_cents"
        case platinumCents = "platinum_cents"
        case perks
    }
}

private struct LTVPolicyPatch: Codable, Sendable {
    let silverCents:   Int
    let goldCents:     Int
    let platinumCents: Int
    let perks:         [LTVPerk]

    enum CodingKeys: String, CodingKey {
        case silverCents   = "silver_cents"
        case goldCents     = "gold_cents"
        case platinumCents = "platinum_cents"
        case perks
    }
}
#endif
