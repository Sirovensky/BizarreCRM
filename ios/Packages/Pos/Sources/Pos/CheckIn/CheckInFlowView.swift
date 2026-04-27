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
            onComplete?(draft)
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
