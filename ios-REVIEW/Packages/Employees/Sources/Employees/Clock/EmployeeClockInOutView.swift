import SwiftUI
import Networking
import DesignSystem
import Core

/// §46 Phase 4 — Clock in/out tile shown inside the Employee detail screen.
///
/// Displays the current clock status for a specific employee and exposes
/// clock-in / clock-out actions via a 4-digit PIN sheet.
///
/// Layout contract:
/// - **iPhone** (compact): compact card; status badge, elapsed time, and
///   a single primary-action button.
/// - **iPad** (regular): wider card with `.hoverEffect(.highlight)` on the
///   action button and a `.keyboardShortcut` for ⌘T (toggle clock).
///
/// Routes used:
/// - `POST /api/v1/employees/:id/clock-in` — body `{ pin }`
/// - `POST /api/v1/employees/:id/clock-out` — body `{ pin }`
/// - `GET  /api/v1/employees/:id` — projects `is_clocked_in` + `current_clock_entry`
public struct EmployeeClockInOutView: View {

    // MARK: - State

    @Bindable var vm: EmployeeClockViewModel
    @State private var pinSheetMode: EmployeePinSheet.Mode?
    @State private var toastMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: - Init

    public init(vm: EmployeeClockViewModel) {
        self.vm = vm
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .bottom) {
            card
            if let toast = toastMessage {
                toastBanner(message: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(BrandMotion.sheet, value: toastMessage)
        .task { await vm.refresh() }
        .onReceive(ticker) { _ in
            guard !reduceMotion else { return }
            vm.tickElapsed()
        }
        .sheet(item: $pinSheetMode) { mode in
            EmployeePinSheet(mode: mode) { pin in
                pinSheetMode = nil
                Task { await performAction(pin: pin, mode: mode) }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Card

    @ViewBuilder
    private var card: some View {
        switch vm.clockState {
        case .idle, .loading:
            loadingCard
        case .notClockedIn:
            clockInCard
        case .clockedIn(let entry):
            clockOutCard(entry: entry)
        case .failed(let msg):
            errorCard(message: msg)
        }
    }

    private var loadingCard: some View {
        HStack {
            ProgressView().tint(.bizarreOrange)
            Text("Loading clock status…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: cardShape)
        .overlay(cardBorder(Color.bizarreOutline.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading clock status")
    }

    private var clockInCard: some View {
        Button { pinSheetMode = .clockIn } label: {
            Label("Clock in", systemImage: "clock.badge.checkmark.fill")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(BrandSpacing.md)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface1, in: cardShape)
        .overlay(cardBorder(Color.bizarreOutline.opacity(0.35)))
        .brandGlass(.regular, in: cardShape, interactive: true)
        .if(!Platform.isCompact) { $0.hoverEffect(.highlight) }
        .keyboardShortcut("t", modifiers: .command)
        .accessibilityLabel("Clock in")
        .accessibilityIdentifier("emp.clock.clockIn")
    }

    private func clockOutCard(entry: ClockEntry) -> some View {
        Button { pinSheetMode = .clockOut } label: {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Label("Clock out", systemImage: "clock.badge.xmark.fill")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.xs) {
                    Text("Since \(formattedTime(entry.clockIn))")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("·").foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(EmployeeClockViewModel.formatElapsed(vm.elapsedSeconds))
                        .font(.brandBodyMedium().monospacedDigit())
                        .foregroundStyle(.bizarreOrange)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(BrandSpacing.md)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface1, in: cardShape)
        .overlay(cardBorder(Color.bizarreOrange.opacity(0.4), lineWidth: 1.0))
        .brandGlass(.regular, in: cardShape, tint: .bizarreOrange, interactive: true)
        .if(!Platform.isCompact) { $0.hoverEffect(.highlight) }
        .keyboardShortcut("t", modifiers: .command)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Clocked in since \(formattedTime(entry.clockIn)). "
            + "Elapsed \(EmployeeClockViewModel.formatElapsed(vm.elapsedSeconds)). "
            + "Tap to clock out."
        )
        .accessibilityIdentifier("emp.clock.clockOut")
    }

    private func errorCard(message: String) -> some View {
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
            Button("Retry") { Task { await vm.refresh() } }
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
                .accessibilityIdentifier("emp.clock.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: cardShape)
        .overlay(cardBorder(Color.bizarreError.opacity(0.4)))
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

    private func performAction(pin: String, mode: EmployeePinSheet.Mode) async {
        switch mode {
        case .clockIn:
            await vm.clockIn(pin: pin)
            if case .clockedIn = vm.clockState {
                BrandHaptics.success()
                showToast("Clocked in")
            }
        case .clockOut:
            await vm.clockOut(pin: pin)
            if case .notClockedIn = vm.clockState {
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

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 16) }

    private func cardBorder(_ color: Color, lineWidth: CGFloat = 0.5) -> some View {
        cardShape.strokeBorder(color, lineWidth: lineWidth)
    }

    private func formattedTime(_ iso8601: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso8601) else { return iso8601 }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - View helper: conditional modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
