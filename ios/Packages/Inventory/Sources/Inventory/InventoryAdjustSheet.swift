import Foundation
import Observation
import Core
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class InventoryAdjustViewModel {
    // MARK: Form state
    public var delta: Int = 0
    public var reason: AdjustReason = .recount
    public var notes: String = ""

    // MARK: Async state
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var newQty: Int?

    public let itemId: Int64
    public let itemName: String

    @ObservationIgnored private let api: APIClient

    public init(itemId: Int64, itemName: String, api: APIClient) {
        self.itemId = itemId
        self.itemName = itemName
        self.api = api
    }

    /// Pure validator — suitable for direct unit-test coverage.
    public var isValid: Bool { validateDelta(delta) }

    /// Returns `true` when `delta` is a non-zero value within safe bounds.
    public func validateDelta(_ value: Int) -> Bool {
        value != 0 && abs(value) <= 1_000_000
    }

    public func submit() async {
        guard !isSubmitting, isValid else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let req = AdjustStockRequest(
            deltaQty: delta,
            reason: reason.serverType,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil
                   : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            let resp = try await api.adjustStock(itemId: itemId, request: req)
            newQty = resp.newQty
        } catch {
            AppLog.ui.error("Inventory adjust failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Reason enum

public enum AdjustReason: String, CaseIterable, Sendable, Identifiable {
    case recount
    case shrinkage
    case damage
    case receive
    case transfer
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .recount:   return "Recount"
        case .shrinkage: return "Shrinkage"
        case .damage:    return "Damage"
        case .receive:   return "Receive"
        case .transfer:  return "Transfer"
        case .other:     return "Other"
        }
    }

    /// Maps to the `type` column the server stores in `stock_movements`.
    var serverType: String {
        switch self {
        case .recount:   return "recount"
        case .shrinkage: return "shrinkage"
        case .damage:    return "damage"
        case .receive:   return "receive"
        case .transfer:  return "transfer"
        case .other:     return "adjustment"
        }
    }
}

// MARK: - View

#if canImport(UIKit)
import SwiftUI
import DesignSystem

public struct InventoryAdjustSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InventoryAdjustViewModel
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onSuccess: (() -> Void)?

    public init(itemId: Int64, itemName: String, api: APIClient, onSuccess: (() -> Void)? = nil) {
        _vm = State(wrappedValue: InventoryAdjustViewModel(itemId: itemId, itemName: itemName, api: api))
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        deltaSection
                        reasonSection
                        notesSection
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }
                    }
                    .padding(BrandSpacing.base)
                }

                if let text = toastText {
                    toastBanner(text)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                        .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle("Adjust stock — \(vm.itemName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Apply") {
                        Task { await applyTapped() }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                    .accessibilityLabel("Apply stock adjustment")
                }
            }
            .presentationDetents(Platform.isCompact ? [.medium] : [.large])
        }
    }

    // MARK: - Sections

    private var deltaSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Quantity change")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            HStack(spacing: BrandSpacing.base) {
                Button {
                    vm.delta -= 1
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(vm.delta < 0 ? Color.bizarreError : Color.bizarreOrange)
                }
                .accessibilityLabel("Decrease quantity")
                .buttonStyle(.plain)

                Text(vm.delta > 0 ? "+\(vm.delta)" : "\(vm.delta)")
                    .font(.brandDisplayMedium())
                    .monospacedDigit()
                    .foregroundStyle(deltaColor)
                    .frame(minWidth: 72)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Delta \(vm.delta)")

                Button {
                    vm.delta += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(vm.delta > 0 ? Color.bizarreSuccess : Color.bizarreOrange)
                }
                .accessibilityLabel("Increase quantity")
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.sm)

            if vm.delta == 0 {
                Text("Set a non-zero quantity to enable Apply.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .cardBackground()
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Reason")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            // Segmented on iPhone (≤3 per row), grid on iPad
            if Platform.isCompact {
                segmentedReasons
            } else {
                gridReasons
            }
        }
        .cardBackground()
    }

    private var segmentedReasons: some View {
        VStack(spacing: BrandSpacing.xs) {
            // Row 1: Recount, Shrinkage, Damage
            HStack(spacing: BrandSpacing.xs) {
                reasonChip(.recount)
                reasonChip(.shrinkage)
                reasonChip(.damage)
            }
            // Row 2: Receive, Transfer, Other
            HStack(spacing: BrandSpacing.xs) {
                reasonChip(.receive)
                reasonChip(.transfer)
                reasonChip(.other)
            }
        }
    }

    private var gridReasons: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: BrandSpacing.xs), count: 6),
            spacing: BrandSpacing.xs
        ) {
            ForEach(AdjustReason.allCases) { r in
                reasonChip(r)
            }
        }
    }

    private func reasonChip(_ r: AdjustReason) -> some View {
        let selected = vm.reason == r
        return Button {
            vm.reason = r
        } label: {
            Text(r.displayName)
                .font(.brandLabelLarge())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
                .background(selected ? Color.bizarreOrange : Color.bizarreSurface1,
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.bizarreOutline.opacity(selected ? 0 : 0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Notes (optional)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("e.g. damaged in transit", text: $vm.notes, axis: .vertical)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(3...6)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
                )
                .accessibilityLabel("Adjustment notes")
        }
        .cardBackground()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
            Text(message)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.sm)
        .background(Color.bizarreError.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.bizarreError.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func toastBanner(_ text: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreSuccess)
            Text(text)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, tint: .bizarreSuccess)
    }

    // MARK: - Helpers

    private var deltaColor: Color {
        if vm.delta > 0 { return .bizarreSuccess }
        if vm.delta < 0 { return .bizarreError }
        return .bizarreOnSurfaceMuted
    }

    private func applyTapped() async {
        await vm.submit()
        guard let qty = vm.newQty else { return }
        // Show success toast, then auto-dismiss.
        let text = "Stock updated — new on-hand \(qty)"
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            toastText = text
        }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            onSuccess?()
            dismiss()
        }
    }
}

// MARK: - Card background (mirrors InventoryDetailView private extension)

private struct AdjustCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func adjustCardBackground() -> some View { modifier(AdjustCardBackground()) }
}
#endif
