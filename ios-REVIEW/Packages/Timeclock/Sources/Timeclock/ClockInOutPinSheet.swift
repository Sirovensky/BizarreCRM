import SwiftUI
import DesignSystem

/// §3.11 — 4-digit PIN entry sheet for clock in/out.
///
/// Reuses the glass-chrome pattern from PosScanSheet. Fires `onApprove`
/// with the entered 4-digit string once all digits are filled; the caller
/// is responsible for actually invoking the clock action.
///
/// The sheet clears its digits on appear so re-presentation is always fresh.
public struct ClockInOutPinSheet: View {
    let mode: Mode
    let onApprove: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits: [Int] = []

    public enum Mode: Sendable, Identifiable {
        case clockIn
        case clockOut

        public var id: String {
            switch self {
            case .clockIn:  return "clockIn"
            case .clockOut: return "clockOut"
            }
        }

        var title: String {
            switch self {
            case .clockIn:  return "Enter PIN to Clock In"
            case .clockOut: return "Enter PIN to Clock Out"
            }
        }

        var icon: String {
            switch self {
            case .clockIn:  return "clock.badge.checkmark.fill"
            case .clockOut: return "clock.badge.xmark.fill"
            }
        }
    }

    public init(mode: Mode, onApprove: @escaping (String) -> Void) {
        self.mode = mode
        self.onApprove = onApprove
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle(mode.title)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("timeclock.pin.cancel")
                }
            }
        }
        .onAppear { digits = [] }
    }

    // MARK: - Body sections

    private var content: some View {
        VStack(spacing: BrandSpacing.xl) {
            modeIcon
            pinDots
            keypad
        }
        .padding(BrandSpacing.lg)
    }

    private var modeIcon: some View {
        Image(systemName: mode.icon)
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(.bizarreOrange)
            .accessibilityHidden(true)
            .padding(.top, BrandSpacing.lg)
    }

    private var pinDots: some View {
        HStack(spacing: BrandSpacing.lg) {
            ForEach(0..<4, id: \.self) { idx in
                Circle()
                    .fill(idx < digits.count ? Color.bizarreOrange : Color.bizarreOutline)
                    .frame(width: 16, height: 16)
                    .animation(BrandMotion.snappy, value: digits.count)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN: \(digits.count) of 4 digits entered")
    }

    private var keypad: some View {
        VStack(spacing: BrandSpacing.md) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                HStack(spacing: BrandSpacing.md) {
                    ForEach(row, id: \.self) { digit in
                        PinKey(label: "\(digit)") { append(digit) }
                    }
                }
            }
            HStack(spacing: BrandSpacing.md) {
                // Empty slot
                Color.clear.frame(width: 80, height: 80)
                PinKey(label: "0") { append(0) }
                PinKey(label: "⌫", isDestructive: true) { deleteLast() }
            }
        }
    }

    // MARK: - Actions

    private func append(_ digit: Int) {
        guard digits.count < 4 else { return }
        BrandHaptics.tap()
        digits.append(digit)
        if digits.count == 4 {
            let pin = digits.map(String.init).joined()
            onApprove(pin)
        }
    }

    private func deleteLast() {
        guard !digits.isEmpty else { return }
        BrandHaptics.tap()
        digits.removeLast()
    }
}

// MARK: - PIN key button

private struct PinKey: View {
    let label: String
    let isDestructive: Bool
    let action: () -> Void

    init(label: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandTitleLarge())
                .foregroundStyle(isDestructive ? .bizarreError : .bizarreOnSurface)
                .frame(width: 80, height: 80)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface1, in: Circle())
        .overlay(Circle().strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
        .brandGlass(.regular, in: Circle(), interactive: true)
        .accessibilityLabel(isDestructive ? "Delete" : label)
        .accessibilityIdentifier("timeclock.pin.key.\(label)")
    }
}
