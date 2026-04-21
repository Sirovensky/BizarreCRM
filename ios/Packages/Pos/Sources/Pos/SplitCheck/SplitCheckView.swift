#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.13 — Split-check overlay presented over the POS cart.
///
/// iPhone: tab-per-party layout (compact, stacked).
/// iPad:   side-by-side columns (one per party).
///
/// Parties are limited to 8 to keep the UI readable.
public struct SplitCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cart: Cart
    let onFinalize: () -> Void

    @State private var vm: SplitCheckViewModel

    public init(cart: Cart, onFinalize: @escaping () -> Void) {
        self.cart        = cart
        self.onFinalize  = onFinalize
        _vm = State(wrappedValue: SplitCheckViewModel(
            mode: .evenly,
            partyCount: 2,
            totalCents: cart.totalCents
        ))
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Group {
                    if Platform.isCompact {
                        iPhoneLayout
                    } else {
                        iPadLayout
                    }
                }
            }
            .navigationTitle("Split Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .presentationDetents(Platform.isCompact ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - iPhone: tabbed per party

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            modeSegment.padding(.horizontal, BrandSpacing.base).padding(.top, BrandSpacing.md)
            TabView {
                ForEach(vm.parties) { party in
                    PartyColumn(party: party, vm: vm, cart: cart)
                        .tabItem {
                            Label(party.label, systemImage: "person")
                        }
                }
            }
        }
    }

    // MARK: - iPad: side-by-side columns

    private var iPadLayout: some View {
        VStack(spacing: 0) {
            modeSegment.padding(.horizontal, BrandSpacing.base).padding(.top, BrandSpacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: BrandSpacing.md) {
                    ForEach(vm.parties) { party in
                        PartyColumn(party: party, vm: vm, cart: cart)
                            .frame(minWidth: 240, maxWidth: 320)
                            .containerRelativeFrame(.horizontal, count: min(vm.parties.count, 3), spacing: BrandSpacing.md)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.md)
            }
        }
    }

    // MARK: - Mode picker

    private var modeSegment: some View {
        Picker("Split mode", selection: Binding(
            get:  { vm.mode },
            set:  { vm.setMode($0) }
        )) {
            Text("Even").tag(SplitCheckMode.evenly)
            Text("By Item").tag(SplitCheckMode.byLineItem)
            Text("Custom").tag(SplitCheckMode.custom)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("splitCheck.modePicker")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Remaining")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(CartMath.formatCents(vm.remainingCents))
                    .font(.brandTitleLarge())
                    .foregroundStyle(vm.remainingCents == 0 ? Color.bizarreOrange : Color.bizarreOnSurface)
                    .monospacedDigit()
            }
            Spacer()
            if vm.parties.count < 8 {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                        vm.addParty()
                    }
                } label: {
                    Label("Add guest", systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityIdentifier("splitCheck.addGuest")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(.bizarreSurface1)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Finalize") {
                BrandHaptics.success()
                onFinalize()
                dismiss()
            }
            .fontWeight(.semibold)
            .disabled(!vm.allPartiesPaid)
            .accessibilityIdentifier("splitCheck.finalize")
        }
    }
}

// MARK: - PartyColumn

/// Single-party column used both on iPhone (as a tab) and iPad (as a column).
private struct PartyColumn: View {
    let party: SplitParty
    let vm:    SplitCheckViewModel
    let cart:  Cart

    @State private var showRename = false
    @State private var pendingName = ""
    @State private var customInput = ""

    var body: some View {
        List {
            Section {
                partyHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            switch vm.mode {
            case .evenly:
                evenSection
            case .byLineItem:
                byItemSection
            case .custom:
                customSection
            }

            paymentSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $pendingName)
            Button("Save") { vm.renameParty(id: party.id, label: pendingName) }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(party.label), owes \(CartMath.formatCents(owedCents)), paid \(CartMath.formatCents(party.paidCents))")
    }

    // MARK: - Header

    private var partyHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(party.label)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Button {
                pendingName = party.label
                showRename  = true
            } label: {
                Image(systemName: "pencil").foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(party.label)")
        }
        .padding(BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .accessibilityIdentifier("splitCheck.partyHeader.\(party.id)")
    }

    // MARK: - Even mode

    @ViewBuilder
    private var evenSection: some View {
        Section("Owes") {
            LabeledContent("Amount") {
                Text(CartMath.formatCents(owedCents))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
            }
            .accessibilityIdentifier("splitCheck.owed.\(party.id)")
        }
    }

    // MARK: - By-item mode

    @ViewBuilder
    private var byItemSection: some View {
        Section("Items") {
            ForEach(cart.items) { item in
                let assigned = vm.assignments[item.id] == party.id
                Button {
                    if assigned {
                        vm.unassign(lineId: item.id)
                    } else {
                        vm.assign(lineId: item.id, to: party.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: assigned ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(assigned ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text(item.name)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(CartMath.formatCents(item.lineSubtotalCents))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.name), \(CartMath.formatCents(item.lineSubtotalCents)), \(assigned ? "assigned" : "unassigned")")
                .accessibilityHint("Double tap to \(assigned ? "unassign" : "assign to \(party.label)")")
                .listRowBackground(Color.bizarreSurface1)
            }
        }
    }

    // MARK: - Custom mode

    @ViewBuilder
    private var customSection: some View {
        Section("Custom amount") {
            HStack {
                Text("$").foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $customInput)
                    .keyboardType(.decimalPad)
                    .onChange(of: customInput) { _, val in
                        if let dollars = Double(val) {
                            vm.setCustomAmount(partyId: party.id, cents: Int(dollars * 100))
                        }
                    }
            }
            .accessibilityIdentifier("splitCheck.customAmount.\(party.id)")
        }
    }

    // MARK: - Payment progress

    @ViewBuilder
    private var paymentSection: some View {
        Section("Payment") {
            let paid = party.paidCents > 0
            Button {
                vm.recordPayment(partyId: party.id, amountCents: owedCents)
                BrandHaptics.success()
            } label: {
                Label(
                    paid ? "Paid \(CartMath.formatCents(party.paidCents))" : "Mark as paid",
                    systemImage: paid ? "checkmark.seal.fill" : "creditcard"
                )
                .foregroundStyle(paid ? Color.bizarreOrange : Color.bizarreOnSurface)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("splitCheck.markPaid.\(party.id)")
        }
    }

    // MARK: - Helpers

    private var owedCents: Int {
        vm.partyOwedCents[party.id] ?? 0
    }
}
#endif
