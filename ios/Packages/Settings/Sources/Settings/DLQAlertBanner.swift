import SwiftUI
import Observation
import Core
import DesignSystem
import Persistence

// MARK: - §19.23 Dead-Letter Queue alert banner
//
// Shown at the app root (above main content) when DLQ count > 0.
// "3 changes couldn't sync — open to fix."
// Tapping navigates to Settings → Data → Dead-letter queue.
// Dismissed by the user or when count drops to zero.
//
// Wiring: App layer places `DLQAlertBanner(onOpenDLQ: ...)` as a `.safeAreaInset(edge: .top)`
// on the root content. The ViewModel polls SyncQueueStore every 30s.

// MARK: - ViewModel

@MainActor
@Observable
public final class DLQAlertBannerViewModel {
    public private(set) var deadLetterCount: Int = 0
    public private(set) var isDismissed: Bool = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init() {}

    public func start() {
        pollTask?.cancel()
        Task { await refresh() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func dismiss() {
        isDismissed = true
    }

    private func refresh() async {
        do {
            let count = try await SyncQueueStore.shared.deadLetterCount()
            deadLetterCount = count
            // Re-show if count increased after a prior dismiss (new failures)
            if count > 0 { isDismissed = false }
        } catch {
            AppLog.sync.error("DLQAlertBanner: refresh failed \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Banner View

/// Glass sticky banner shown at the app root when the dead-letter queue has entries.
/// Place as `.safeAreaInset(edge: .top) { DLQAlertBanner(vm: vm, onOpenDLQ: { ... }) }`.
public struct DLQAlertBanner: View {
    public var vm: DLQAlertBannerViewModel
    /// Called when the user taps "Fix now" — should navigate to Settings → Data → Dead-letter.
    public var onOpenDLQ: (() -> Void)?

    public init(vm: DLQAlertBannerViewModel, onOpenDLQ: (() -> Void)? = nil) {
        self.vm = vm
        self.onOpenDLQ = onOpenDLQ
    }

    public var body: some View {
        if vm.deadLetterCount > 0 && !vm.isDismissed {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)

                Text("\(vm.deadLetterCount) change\(vm.deadLetterCount == 1 ? "" : "s") couldn't sync")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)

                Spacer(minLength: 0)

                Button("Fix now") {
                    onOpenDLQ?()
                }
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Open dead-letter queue to fix sync errors")

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        vm.dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Dismiss sync error banner")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(Color.bizarreOutline.opacity(0.35)),
                alignment: .bottom
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .task { vm.start() }
            .onDisappear { vm.stop() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(vm.deadLetterCount) sync changes failed. Tap Fix now to review.")
            .accessibilityAddTraits(.isButton)
        }
    }
}
