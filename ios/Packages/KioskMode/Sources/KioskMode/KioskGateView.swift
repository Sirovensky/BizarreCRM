import SwiftUI
import Core
import DesignSystem

// MARK: - KioskGateView

/// §55.1 / §55.2 Wraps app content and filters based on active kiosk mode.
/// Exit requires Manager PIN when kiosk is active.
public struct KioskGateView<POSContent: View, ClockContent: View, FullContent: View>: View {
    @Bindable var kioskManager: KioskModeManager
    @Bindable var idleMonitor: KioskIdleMonitor
    @Bindable var trainingManager: TrainingModeManager

    let posContent: () -> POSContent
    let clockContent: () -> ClockContent
    let fullContent: () -> FullContent

    @State private var showPinSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        kioskManager: KioskModeManager,
        idleMonitor: KioskIdleMonitor,
        trainingManager: TrainingModeManager,
        @ViewBuilder posContent: @escaping () -> POSContent,
        @ViewBuilder clockContent: @escaping () -> ClockContent,
        @ViewBuilder fullContent: @escaping () -> FullContent
    ) {
        self.kioskManager = kioskManager
        self.idleMonitor = idleMonitor
        self.trainingManager = trainingManager
        self.posContent = posContent
        self.clockContent = clockContent
        self.fullContent = fullContent
    }

    public var body: some View {
        ZStack {
            modeContent
                .trainingModeWatermark(isActive: trainingManager.isActive)

            // Idle dim overlay
            if idleMonitor.idleState == .dimmed {
                dimOverlay
            }

            // Blackout overlay
            if idleMonitor.idleState == .blackout {
                blackoutOverlay
            }
        }
        .onAppear {
            if kioskManager.isKioskActive {
                idleMonitor.start()
            }
        }
        .onDisappear {
            idleMonitor.stop()
        }
        .onChange(of: kioskManager.currentMode) { _, mode in
            if mode == .off {
                idleMonitor.stop()
            } else {
                idleMonitor.start()
            }
        }
        .sheet(isPresented: $showPinSheet) {
            ManagerPinSheet(
                onSuccess: {
                    showPinSheet = false
                    kioskManager.setMode(.off)
                },
                onCancel: {
                    showPinSheet = false
                }
            )
        }
    }

    // MARK: - Mode content routing

    @ViewBuilder
    private var modeContent: some View {
        switch kioskManager.currentMode {
        case .off:
            fullContent()
        case .posOnly:
            posKioskWrapper
        case .clockInOnly:
            clockKioskWrapper
        case .training:
            TrainingProfileView(
                onExitRequest: { showPinSheet = true },
                idleMonitor: idleMonitor
            )
        }
    }

    // MARK: - POS kiosk wrapper

    private var posKioskWrapper: some View {
        VStack(spacing: 0) {
            posContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            kioskExitBar
        }
        .onTapGesture { idleMonitor.recordActivity() }
    }

    // MARK: - Clock kiosk wrapper

    private var clockKioskWrapper: some View {
        VStack(spacing: 0) {
            clockContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            kioskExitBar
        }
        .onTapGesture { idleMonitor.recordActivity() }
    }

    // MARK: - Exit bar

    private var kioskExitBar: some View {
        HStack {
            Spacer()
            Button {
                showPinSheet = true
            } label: {
                Label("Exit Kiosk", systemImage: "lock.open")
                    .font(.footnote)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .background(.regularMaterial)
    }

    // MARK: - Idle overlays

    private var dimOverlay: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityLabel("Screen dimmed — tap to resume")
            .accessibilityAddTraits(.isButton)
            .onTapGesture { idleMonitor.recordActivity() }
            .animation(.easeIn(duration: DesignTokens.Motion.smooth), value: idleMonitor.idleState)
    }

    private var blackoutOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.xl) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .burnInNudge(every: 30)

                Text("BizarreCRM")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .burnInNudge(every: 30)

                Text("Tap to wake")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Screen is sleeping — tap to resume")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { idleMonitor.recordActivity() }
    }
}
