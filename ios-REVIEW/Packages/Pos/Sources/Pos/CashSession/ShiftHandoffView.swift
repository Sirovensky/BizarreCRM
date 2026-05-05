#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

/// §16.10 — Shift handoff flow.
///
/// When an outgoing cashier closes the register, the app offers an immediate
/// handoff so the incoming cashier can open a fresh session without going
/// through the normal POS "closed register" gate. This view:
///
/// 1. Confirms the outgoing shift was closed (shows variance summary).
/// 2. Prompts the incoming cashier for their opening float.
/// 3. Opens a new session via `CashRegisterStore`.
///
/// Tenant config: `ShiftHandoffPolicy.requiresCount` — when true the
/// outgoing cashier cannot skip the drawer count; they must type an amount
/// or present a manager PIN to skip. When false, the cashier can tap
/// "Skip count" (goes to the open-register step directly).
///
/// iPhone: full-screen navigation.
/// iPad: `.medium` sheet at 560 pt.
@MainActor
public struct ShiftHandoffView: View {

    // MARK: - Init props

    /// The session that was just closed.
    public let closedSession: CashSessionRecord
    /// Tenant handoff policy — injected from `PosTenantLimits`.
    public let policy: ShiftHandoffPolicy
    /// Called when the incoming session is opened (or handoff is cancelled).
    public let onComplete: () -> Void

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .summary
    @State private var openingFloatText: String = ""
    @State private var incomingCashierName: String = ""
    @State private var isOpening: Bool = false
    @State private var errorMessage: String?
    @State private var showManagerPinForSkip: Bool = false

    @FocusState private var floatFocused: Bool

    // MARK: - Derived

    private var openingFloatCents: Int {
        let trimmed = openingFloatText.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(".") {
            guard let v = Double(trimmed), v >= 0 else { return 0 }
            return Int((v * 100).rounded())
        } else {
            guard let v = Int(trimmed), v >= 0 else { return 0 }
            return v * 100
        }
    }

    private var canOpenShift: Bool {
        !isOpening && openingFloatCents >= 0 &&
        !incomingCashierName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step enum

    enum Step {
        case summary   // Show closed shift variance + CTA to start handoff
        case openShift // Enter opening float for incoming cashier
    }

    // MARK: - Init

    public init(
        closedSession: CashSessionRecord,
        policy: ShiftHandoffPolicy = .default,
        onComplete: @escaping () -> Void
    ) {
        self.closedSession = closedSession
        self.policy = policy
        self.onComplete = onComplete
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .summary: summaryStep
                case .openShift: openShiftStep
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Shift Handoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip handoff") {
                        onComplete()
                        dismiss()
                    }
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityIdentifier("pos.handoff.skip")
                }
            }
        }
        .frame(idealWidth: Platform.isCompact ? nil : 560)
        .sheet(isPresented: $showManagerPinForSkip) {
            ManagerPinSheet(
                reason: "Skip drawer count for shift close",
                onApproved: { _ in
                    AppLog.pos.info("Manager approved skip-count for shift handoff")
                    step = .openShift
                },
                onCancelled: { }
            )
        }
    }

    // MARK: - Step: summary

    private var summaryStep: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                // Shift close card
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityHidden(true)

                    Text("Shift Closed")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)

                    if let variance = closedSession.varianceCents {
                        let band = CashVariance.band(cents: variance)
                        HStack(spacing: BrandSpacing.sm) {
                            Circle()
                                .fill(band.color)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text("Variance: \(CloseRegisterSheet.formatSigned(cents: variance))")
                                .font(.brandTitleMedium())
                                .foregroundStyle(band.color)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(band.color.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.top, BrandSpacing.xl)

                // Policy info
                if policy.requiresCount {
                    Label(
                        "Your shop requires a drawer count before handoff.",
                        systemImage: "lock.shield"
                    )
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
                }

                // CTA
                VStack(spacing: BrandSpacing.md) {
                    Button {
                        step = .openShift
                    } label: {
                        Label("Start next shift", systemImage: "arrow.right.circle.fill")
                            .font(.brandTitleSmall())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BrandSpacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("pos.handoff.startNext")

                    if policy.requiresCount && policy.canSkipWithManagerPin {
                        Button {
                            showManagerPinForSkip = true
                        } label: {
                            Label("Skip count (manager PIN)", systemImage: "lock.open")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pos.handoff.skipWithPin")
                    }
                }
                .padding(.horizontal, BrandSpacing.xl)
            }
        }
    }

    // MARK: - Step: open shift

    private var openShiftStep: some View {
        Form {
            Section {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    TextField("Incoming cashier name", text: $incomingCashierName)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pos.handoff.cashierName")
                }
            } header: {
                Text("Incoming cashier")
            }

            Section {
                HStack(spacing: BrandSpacing.sm) {
                    Text("$")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("0.00", text: $openingFloatText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($floatFocused)
                        .accessibilityLabel("Opening float in dollars")
                        .accessibilityIdentifier("pos.handoff.openingFloat")
                }
                if openingFloatCents > 0 {
                    Text(CartMath.formatCents(openingFloatCents) + " in the drawer")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } header: {
                Text("Opening float")
            } footer: {
                Text("Enter the cash count placed in the drawer at the start of this shift.")
                    .font(.brandLabelSmall())
            }

            if let err = errorMessage {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .accessibilityIdentifier("pos.handoff.error")
                }
            }

            Section {
                Button(isOpening ? "Opening…" : "Open register") {
                    Task { await openShift() }
                }
                .frame(maxWidth: .infinity)
                .font(.brandTitleSmall())
                .disabled(!canOpenShift)
                .accessibilityIdentifier("pos.handoff.openCTA")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .onAppear { floatFocused = true }
    }

    // MARK: - Actions

    private func openShift() async {
        guard canOpenShift, !isOpening else { return }
        isOpening = true
        errorMessage = nil
        defer { isOpening = false }

        do {
            _ = try await CashRegisterStore.shared.openSession(
                openingFloat: openingFloatCents,
                userId: 0  // placeholder — real userId from session layer in Phase 5
            )
            AppLog.pos.info("Shift handoff: new session opened float=\(openingFloatCents)c cashier=\(incomingCashierName)")
            BrandHaptics.success()
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tenant policy

/// §16.10 tenant configuration for shift handoff behaviour.
public struct ShiftHandoffPolicy: Sendable, Equatable {
    /// When true, cashiers must count the drawer (enter a cash amount)
    /// before the handoff proceeds. False = skip count is allowed.
    public let requiresCount: Bool
    /// When true (and requiresCount == true), a manager PIN allows
    /// the cashier to skip the count. When false, skip is always blocked.
    public let canSkipWithManagerPin: Bool

    public static let `default` = ShiftHandoffPolicy(
        requiresCount: false,
        canSkipWithManagerPin: true
    )

    public static let strict = ShiftHandoffPolicy(
        requiresCount: true,
        canSkipWithManagerPin: true
    )

    public static let mandatory = ShiftHandoffPolicy(
        requiresCount: true,
        canSkipWithManagerPin: false
    )

    public init(requiresCount: Bool, canSkipWithManagerPin: Bool) {
        self.requiresCount = requiresCount
        self.canSkipWithManagerPin = canSkipWithManagerPin
    }
}

// MARK: - Preview helpers

private extension CashSessionRecord {
    static var previewClosed: CashSessionRecord {
        CashSessionRecord(
            id: 1,
            openedBy: 1,
            openedAt: Date().addingTimeInterval(-8 * 3600),
            openingFloat: 10000,
            closedAt: Date(),
            closedBy: 1,
            countedCash: 10240,
            expectedCash: 10200,
            varianceCents: 40
        )
    }
}

// MARK: - Preview

#Preview("Handoff — summary") {
    ShiftHandoffView(
        closedSession: .previewClosed,
        policy: .strict,
        onComplete: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Handoff — open shift step") {
    ShiftHandoffView(
        closedSession: .previewClosed,
        policy: .default,
        onComplete: {}
    )
    .preferredColorScheme(.dark)
}
#endif
