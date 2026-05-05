import SwiftUI
import DesignSystem
import Core
import Networking

/// §3.11 — Dashboard tile for one-tap clock in / clock out.
///
/// States
/// - idle   → large "Clock in" button with `.brandGlass` chrome.
/// - active → "Clock out · HH:MM AM/PM" button with running elapsed time.
/// - loading → progress spinner while a clock action is in flight.
/// - failed  → inline error with a retry button.
///
/// Elapsed updates every 30 s via `Timer.publish` unless the user has
/// enabled Reduce Motion (in which case the ticker is suspended to avoid
/// layout thrash from sub-second animations).
///
/// The tile calls `ClockInOutViewModel` methods; if the tenant requires
/// a PIN the tap triggers `ClockInOutPinSheet`. PIN requirement is
/// heuristically detected: if the first clock attempt fails with HTTP 401
/// we show the sheet on the next tap.
public struct ClockInOutTile: View {
    @Bindable var vm: ClockInOutViewModel

    /// Whether the PIN sheet is presented and for which mode.
    @State private var pinSheetMode: ClockInOutPinSheet.Mode?
    /// Toast message to display briefly after a successful clock action.
    @State private var toastMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 30-second ticker to update elapsed time.
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    public init(vm: ClockInOutViewModel) {
        self.vm = vm
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            tile
            if let toast = toastMessage {
                toastBanner(message: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(BrandMotion.sheet, value: toastMessage)
        .task { await vm.refresh() }
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            vm.tickElapsed()
        }
        .sheet(item: $pinSheetMode) { mode in
            ClockInOutPinSheet(mode: mode) { pin in
                pinSheetMode = nil
                Task {
                    await performAction(pin: pin, mode: mode)
                }
            }
        }
    }

    // MARK: - Tile body

    @ViewBuilder
    private var tile: some View {
        switch vm.state {
        case .loading:
            loadingTile
        case .idle:
            clockInButton
        case .active(let entry):
            clockOutButton(entry: entry)
        case .failed(let msg):
            failureTile(message: msg)
        }
    }

    private var loadingTile: some View {
        HStack {
            ProgressView()
                .tint(.bizarreOrange)
            Text("Loading clock status…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading clock status")
    }

    private var clockInButton: some View {
        Button {
            handleClockIn()
        } label: {
            Label("Clock in", systemImage: "clock.badge.checkmark.fill")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(BrandSpacing.md)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16), interactive: true)
        .accessibilityLabel("Clock in")
        .accessibilityIdentifier("timeclock.clockIn")
    }

    private func clockOutButton(entry: ClockEntry) -> some View {
        Button {
            handleClockOut()
        } label: {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Label("Clock out", systemImage: "clock.badge.xmark.fill")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.xs) {
                    Text("Since \(formattedClockInTime(entry.clockIn))")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("·")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(ClockInOutViewModel.formatElapsed(vm.runningElapsed))
                        .font(.brandBodyMedium().monospacedDigit())
                        .foregroundStyle(.bizarreOrange)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .padding(BrandSpacing.md)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOrange.opacity(0.4), lineWidth: 1.0)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16), tint: .bizarreOrange, interactive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clocked in since \(formattedClockInTime(entry.clockIn)). Elapsed \(ClockInOutViewModel.formatElapsed(vm.runningElapsed)). Tap to clock out.")
        .accessibilityIdentifier("timeclock.clockOut")
    }

    private func failureTile(message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Clock status unavailable")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(message)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: BrandSpacing.sm)
            Button("Retry") {
                Task { await vm.refresh() }
            }
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOrange)
            .accessibilityIdentifier("timeclock.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreError.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Toast

    private func toastBanner(message: String) -> some View {
        Text(message)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .brandGlass(.regular, in: Capsule())
            .padding(.bottom, BrandSpacing.sm)
            .accessibilityLabel(message)
    }

    // MARK: - Actions

    private func handleClockIn() {
        // Pass empty pin — if the server returns 401, the view model's state
        // will flip to .failed and the user can see an error. A future UX
        // improvement could detect 401 and automatically show the PIN sheet;
        // for now present it immediately to match the spec ("if Settings requires it").
        pinSheetMode = .clockIn
    }

    private func handleClockOut() {
        pinSheetMode = .clockOut
    }

    private func performAction(pin: String, mode: ClockInOutPinSheet.Mode) async {
        switch mode {
        case .clockIn:
            await vm.clockIn(pin: pin)
            if case .active = vm.state {
                BrandHaptics.success()
                showToast("Clocked in")
            }
        case .clockOut:
            await vm.clockOut(pin: pin)
            if case .idle = vm.state {
                BrandHaptics.success()
                showToast("Clocked out")
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            toastMessage = nil
        }
    }

    // MARK: - Helpers

    private func formattedClockInTime(_ iso8601: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso8601) else {
            return iso8601
        }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
