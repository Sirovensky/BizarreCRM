#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.7 Late fee waiver — staff can waive an applied late fee with reason + audit.
// Threshold above which a manager PIN is required (default $50 = 5 000 cents).
// Endpoint: POST /api/v1/invoices/:id/waive-late-fee  { reason, amount_cents }
// Server writes an audit log entry on every successful waiver.

// MARK: - Waiver threshold

/// Manager PIN is required when the late fee waiver amount exceeds this threshold.
public let kLateFeeWaiverManagerPinThresholdCents: Int = 5_000

// MARK: - Request / Response

public struct WaiveLateFeeRequest: Encodable, Sendable {
    public let reason: String
    /// Amount to waive in cents (must be ≤ the applied late fee).
    public let amountCents: Int

    public init(reason: String, amountCents: Int) {
        self.reason = reason
        self.amountCents = amountCents
    }

    enum CodingKeys: String, CodingKey {
        case reason
        case amountCents = "amount_cents"
    }
}

public struct WaiveLateFeeResponse: Decodable, Sendable {
    public let success: Bool?
    public let message: String?
}

public extension APIClient {
    /// `POST /api/v1/invoices/:id/waive-late-fee`
    /// Role-gated: manager or admin. Audit entry created server-side.
    func waiveLateFee(invoiceId: Int64, body: WaiveLateFeeRequest) async throws -> WaiveLateFeeResponse {
        try await post(
            "/api/v1/invoices/\(invoiceId)/waive-late-fee",
            body: body,
            as: WaiveLateFeeResponse.self
        )
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class LateFeeWaiverViewModel {

    public enum WaiverState: Sendable, Equatable {
        case idle
        case submitting
        case success
        case failed(String)
    }

    // Form
    public var amountString: String = "" {
        didSet {
            if let d = Double(amountString.filter { $0.isNumber || $0 == "." }) {
                amountCents = Int((d * 100).rounded())
            }
        }
    }
    public var amountCents: Int = 0
    public var reason: String = ""
    public var managerPin: String = ""
    public var showManagerPinPrompt: Bool = false

    // State
    public private(set) var state: WaiverState = .idle

    @ObservationIgnored private let api: APIClient
    public let invoiceId: Int64
    /// Maximum waivable amount in cents (the applied late fee).
    public let maxWaiverCents: Int

    public init(api: APIClient, invoiceId: Int64, maxWaiverCents: Int) {
        self.api = api
        self.invoiceId = invoiceId
        self.maxWaiverCents = maxWaiverCents
        // Pre-seed with full fee amount.
        self.amountCents = maxWaiverCents
        self.amountString = String(format: "%.2f", Double(maxWaiverCents) / 100.0)
    }

    public var requiresManagerPin: Bool {
        amountCents > kLateFeeWaiverManagerPinThresholdCents
    }

    public var isValid: Bool {
        amountCents > 0
            && amountCents <= maxWaiverCents
            && !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func submit() async {
        guard isValid else { return }
        if requiresManagerPin && managerPin.isEmpty {
            showManagerPinPrompt = true
            return
        }
        guard case .idle = state else { return }
        state = .submitting

        do {
            _ = try await api.waiveLateFee(
                invoiceId: invoiceId,
                body: WaiveLateFeeRequest(
                    reason: reason.trimmingCharacters(in: .whitespaces),
                    amountCents: amountCents
                )
            )
            state = .success
        } catch {
            AppLog.ui.error("Late fee waiver failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(AppError.from(error).errorDescription ?? "Waiver failed.")
        }
    }

    public func submitWithPin(_ pin: String) async {
        managerPin = pin
        showManagerPinPrompt = false
        state = .idle
        await submit()
    }

    public func resetToIdle() {
        if case .failed = state { state = .idle }
    }
}

// MARK: - Sheet

public struct LateFeeWaiverSheet: View {
    @State private var vm: LateFeeWaiverViewModel
    @Environment(\.dismiss) private var dismiss

    let onSuccess: () -> Void

    public init(vm: LateFeeWaiverViewModel, onSuccess: @escaping () -> Void) {
        _vm = State(wrappedValue: vm)
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        maxFeeCard
                        amountSection
                        reasonSection
                        if vm.requiresManagerPin {
                            pinRequiredBadge
                        }
                        submitButton
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Waive Late Fee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Cancel late fee waiver")
                }
            }
            .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .presentationDetents([Platform.isCompact ? .medium : .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $vm.showManagerPinPrompt) {
            WaiverManagerPinSheet { pin in
                Task { await vm.submitWithPin(pin) }
            }
        }
        .onChange(of: vm.state) { _, newState in
            if case .success = newState {
                onSuccess()
                dismiss()
            }
        }
        .alert("Waiver Failed", isPresented: .constant({
            if case .failed = vm.state { return true }
            return false
        }())) {
            Button("OK") { vm.resetToIdle() }
        } message: {
            if case let .failed(msg) = vm.state { Text(msg) }
        }
    }

    // MARK: - Sections

    private var maxFeeCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Applied Late Fee")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.maxWaiverCents))
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text("Waiving")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(formatCents(vm.amountCents))
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreSuccess)
                    .monospacedDigit()
            }
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Applied late fee \(formatCents(vm.maxWaiverCents)). Waiving \(formatCents(vm.amountCents)).")
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Waiver Amount")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            HStack {
                Text("$").font(.brandHeadlineMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $vm.amountString)
                    .keyboardType(.decimalPad)
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Waiver amount in dollars")
            }
            if vm.amountCents > vm.maxWaiverCents {
                Text("Cannot exceed the applied late fee.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        }
        .cardBackground()
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Reason for Waiver")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("Explain why the late fee is being waived…", text: $vm.reason, axis: .vertical)
                .lineLimit(3...5)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .accessibilityLabel("Waiver reason text field")
        }
        .cardBackground()
    }

    private var pinRequiredBadge: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "lock.shield.fill").foregroundStyle(.bizarreWarning)
            Text("Manager PIN required above $\(kLateFeeWaiverManagerPinThresholdCents / 100).")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreWarning.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityLabel("Manager PIN required for this waiver amount.")
    }

    private var submitButton: some View {
        Button {
            Task { await vm.submit() }
        } label: {
            Group {
                if case .submitting = vm.state {
                    ProgressView().tint(.white)
                } else {
                    HStack {
                        if vm.requiresManagerPin {
                            Image(systemName: "lock.shield")
                        }
                        Text(vm.requiresManagerPin ? "Authorize & Waive Fee" : "Waive Late Fee")
                            .font(.brandTitleMedium())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                    tint: .bizarreSuccess,
                    interactive: true)
        .foregroundStyle(.white)
        .disabled(!vm.isValid || {
            if case .submitting = vm.state { return true }
            return false
        }())
        .accessibilityLabel(vm.requiresManagerPin
            ? "Authorize and waive late fee — requires manager PIN"
            : "Waive late fee")
    }
}

// MARK: - Manager PIN sheet for waiver

private struct WaiverManagerPinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    let onConfirm: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreOrange)

                    Text("Manager Authorization Required")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .multilineTextAlignment(.center)

                    Text("Waivers over $\(kLateFeeWaiverManagerPinThresholdCents / 100) require a manager PIN.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)

                    SecureField("Enter PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.brandHeadlineMedium())
                        .multilineTextAlignment(.center)
                        .padding(BrandSpacing.base)
                        .background(Color.bizarreSurface1,
                                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1))
                        .accessibilityLabel("Manager PIN entry field")

                    Button {
                        onConfirm(pin)
                        dismiss()
                    } label: {
                        Text("Authorize Waiver")
                            .font(.brandTitleMedium())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BrandSpacing.md)
                    }
                    .brandGlass(.regular,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                                tint: .bizarreOrange,
                                interactive: true)
                    .foregroundStyle(.white)
                    .disabled(pin.isEmpty)
                    .accessibilityLabel("Authorize fee waiver with manager PIN")
                }
                .padding(BrandSpacing.xl)
            }
            .navigationTitle("Manager PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel manager PIN entry")
                }
            }
            .toolbarBackground(.bizarreSurface1, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Helpers

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}

private func formatCents(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
}
#endif
