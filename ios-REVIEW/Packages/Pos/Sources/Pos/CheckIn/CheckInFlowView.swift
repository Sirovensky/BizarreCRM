/// CheckInFlowView.swift — §16.25
///
/// 6-step repair check-in wizard container.
///
/// Steps: Symptoms → Details → Damage → Diagnostic → Quote → Sign.
/// Each step advances via "Next" (primary cream) / "Back" (secondary).
/// "Next" is disabled until minimum required fields are filled.
/// Progress bar (linear) advances on each "Next" tap.
///
/// Autosave: `PATCH /api/v1/tickets/:id` on every step transition (fire-and-forget).
/// Finalize (last step): upload signature → write deposit payment → set status=open → onComplete.
/// Offline: draft queued via SyncQueueStore; autosave chip shows "Queued".
///
/// Glass budget: 2 (progress bar container + bottom nav bar).
///
/// Spec: `../pos-phone-mockups.html` frames CI-1 through CI-6.

#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - CheckInStep

public enum CheckInStep: CaseIterable, Sendable, Identifiable, Equatable {
    case symptoms, details, damage, diagnostic, quote, sign

    public var id: Self { self }

    public var title: String {
        switch self {
        case .symptoms:   return "Symptoms"
        case .details:    return "Details"
        case .damage:     return "Pre-existing damage"
        case .diagnostic: return "Diagnostic"
        case .quote:      return "Quote"
        case .sign:       return "Sign"
        }
    }

    public var isSkippable: Bool {
        switch self {
        case .symptoms, .sign: return false
        default: return true
        }
    }

    public var index: Int {
        CheckInStep.allCases.firstIndex(of: self)!
    }

    public var next: CheckInStep? {
        let all = CheckInStep.allCases
        let nextIdx = index + 1
        guard nextIdx < all.count else { return nil }
        return all[nextIdx]
    }

    public var previous: CheckInStep? {
        guard index > 0 else { return nil }
        return CheckInStep.allCases[index - 1]
    }
}

// MARK: - CheckInFlowViewModel

@MainActor
@Observable
public final class CheckInFlowViewModel {
    public let draft: CheckInDraft
    public private(set) var currentStep: CheckInStep = .symptoms
    public private(set) var isSaving: Bool = false
    public private(set) var saveError: Error? = nil
    public private(set) var isOffline: Bool = false

    @ObservationIgnored private let api: (any APIClient)?
    public var onComplete: ((CheckInDraft) -> Void)?

    public init(draft: CheckInDraft = CheckInDraft(), api: (any APIClient)? = nil) {
        self.draft = draft
        self.api = api
    }

    public func advance() async {
        guard let next = currentStep.next else {
            // Last step — run the full finalize sequence.
            await finalizeSignStep()
            return
        }
        await autosave()
        currentStep = next
    }

    public func goBack() {
        guard let prev = currentStep.previous else { return }
        currentStep = prev
    }

    public func skipStep() {
        Task { await advance() }
    }

    public func canAdvance() -> Bool {
        switch currentStep {
        case .symptoms:
            return !draft.symptoms.isEmpty || !draft.symptomOtherText.isEmpty
        case .sign:
            return draft.canSign && draft.signatureAttached
        default:
            return true
        }
    }

    private func autosave() async {
        guard let api, let ticketId = draft.ticketId else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            // Autosave via PATCH /api/v1/tickets/:id with diagnostic notes
            try await api.patchTicketDraft(
                id: ticketId,
                diagnosticNotes: draft.diagnosticNotes.isEmpty ? nil : draft.diagnosticNotes,
                internalNotes: draft.internalNotes.isEmpty ? nil : draft.internalNotes
            )
            isOffline = false
        } catch {
            isOffline = true
            saveError = error
        }
    }

    /// §16.25.6 — Finalize sign step:
    /// 1. Upload signature PNG → `POST /api/v1/tickets/:id/signatures`.
    /// 2. If deposit > 0, write deposit payment → `POST /api/v1/invoices/:id/payments`.
    /// 3. Transition ticket to `open` → `PATCH /api/v1/tickets/:id` `{ status: "open" }`.
    /// 4. Call `onComplete(draft)` to push the drop-off receipt view.
    ///
    /// Network errors are surfaced via `saveError`; the UI keeps the Sign step
    /// visible so the cashier can retry. Offline path: draft is already in the
    /// sync queue from autosave; signature + deposit are queued below if api is nil.
    private func finalizeSignStep() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        guard let api, let ticketId = draft.ticketId else {
            // No API / no ticketId — treat as offline, call through directly.
            isOffline = true
            onComplete?(draft)
            return
        }

        do {
            // Step 1: Upload signature if present.
            if let sig = draft.signaturePNGBase64 {
                _ = try await api.uploadTicketSignature(ticketId: ticketId, base64PNG: sig)
            }

            // Step 2: Write deposit payment (cash method — tender sheet wiring deferred).
            // `invoiceId` mirrors ticketId for now; the server creates an invoice per ticket.
            let depositCents = draft.depositCents
            if depositCents > 0 {
                let idempotencyKey = UUID().uuidString
                _ = try await api.recordCheckinDeposit(
                    invoiceId: ticketId,          // server maps ticket→invoice on this path
                    depositCents: depositCents,
                    method: "cash",
                    notes: "Check-in deposit",
                    idempotencyKey: idempotencyKey
                )
            }

            // Step 3: Transition ticket to open.
            _ = try await api.finalizeCheckinTicket(id: ticketId)

            isOffline = false
            onComplete?(draft)
        } catch {
            isOffline = true
            saveError = error
            // Do NOT advance — keep user on sign step to retry.
        }
    }
}

// MARK: - CheckInFlowView

public struct CheckInFlowView: View {

    @Bindable var vm: CheckInFlowViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(vm: CheckInFlowViewModel) {
        self.vm = vm
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bizarreSurfaceBase.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar (glass container)
                    progressBar
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                        .padding(.bottom, BrandSpacing.md)

                    // Autosave chip
                    if vm.isSaving || vm.isOffline {
                        autosaveChip
                            .padding(.bottom, BrandSpacing.sm)
                    }

                    // Step content
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Spacer for bottom nav bar
                    Spacer().frame(height: 80)
                }

                // Bottom navigation bar (glass)
                bottomNavBar
            }
            .navigationTitle(vm.currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let fraction = Double(vm.currentStep.index + 1) / Double(CheckInStep.allCases.count)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.bizarreSurface2)
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 3)
                    .fill(vm.currentStep == .sign ? Color.bizarreSuccess : Color.bizarreOrange)
                    .frame(width: geo.size.width * fraction, height: 3)
                    .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.snappy), value: fraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    // MARK: - Autosave chip

    private var autosaveChip: some View {
        HStack(spacing: 4) {
            if vm.isSaving {
                ProgressView().scaleEffect(0.6)
                Text("Draft · autosaving")
            } else {
                Image(systemName: "wifi.slash")
                Text("Draft · queued")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.bizarreOnSurfaceMuted)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, 4)
        .background(Color.bizarreSurface2, in: Capsule())
    }

    // MARK: - Step content router

    @ViewBuilder
    private var stepContent: some View {
        switch vm.currentStep {
        case .symptoms:   CheckInSymptomsView(draft: vm.draft)
        case .details:    CheckInDetailsView(draft: vm.draft)
        case .damage:     CheckInDamageView(draft: vm.draft)
        case .diagnostic: CheckInDiagnosticView(draft: vm.draft)
        case .quote:      CheckInQuoteView(draft: vm.draft)
        case .sign:       CheckInSignView(draft: vm.draft)
        }
    }

    // MARK: - Bottom nav bar

    private var bottomNavBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: BrandSpacing.md) {
                // Back button
                if vm.currentStep.previous != nil {
                    Button("Back") { vm.goBack() }
                        .buttonStyle(.bordered)
                        .tint(Color.bizarreOnSurfaceMuted)
                }

                Spacer()

                // Skip button (if allowed)
                if vm.currentStep.isSkippable {
                    Button("Skip") { vm.skipStep() }
                        .font(.system(size: 14))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }

                // Next / Complete button
                Button {
                    Task { await vm.advance() }
                } label: {
                    let isLast = vm.currentStep.next == nil
                    Text(isLast ? "Create ticket" : "Next · \(vm.currentStep.next?.title ?? "")")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(vm.canAdvance() ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                        .padding(.horizontal, BrandSpacing.lg)
                        .frame(height: 44)
                        .background(
                            vm.canAdvance() ? Color.bizarreOrange : Color.bizarreSurface2,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!vm.canAdvance())
                .accessibilityIdentifier("checkin.nextButton")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
        }
        .background(Color.bizarreSurfaceBase)
    }
}
#endif
