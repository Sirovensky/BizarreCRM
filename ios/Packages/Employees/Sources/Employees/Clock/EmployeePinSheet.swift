import SwiftUI
import DesignSystem

/// §46 Phase 4 — 4-digit PIN entry sheet used by `EmployeeClockInOutView`.
///
/// Mirrors the UX of the Timeclock package's `ClockInOutPinSheet` but lives
/// inside `Employees` so there is no cross-package import. Fires `onApprove`
/// with the 4-digit string once all digits are entered; the caller invokes
/// the actual clock action.
public struct EmployeePinSheet: View {

    // MARK: - Types

    public enum Mode: Sendable, Identifiable {
        case clockIn
        case clockOut

        public var id: String {
            switch self {
            case .clockIn:  return "emp-clockIn"
            case .clockOut: return "emp-clockOut"
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

    // MARK: - Properties

    let mode: Mode
    let onApprove: @MainActor (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits: [Int] = []

    // MARK: - Init

    public init(mode: Mode, onApprove: @escaping @MainActor (String) -> Void) {
        self.mode = mode
        self.onApprove = onApprove
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    modeIcon
                    pinDots
                    keypad
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle(mode.title)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("emp.pin.cancel")
                }
            }
        }
        .onAppear { digits = [] }
    }

    // MARK: - Sections

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
                        PinKey(label: "\(digit)") { appendDigit(digit) }
                    }
                }
            }
            HStack(spacing: BrandSpacing.md) {
                Color.clear.frame(width: 80, height: 80)
                PinKey(label: "0") { appendDigit(0) }
                PinKey(label: "⌫", isDestructive: true) { deleteLastDigit() }
            }
        }
    }

    // MARK: - Actions

    private func appendDigit(_ digit: Int) {
        guard digits.count < 4 else { return }
        BrandHaptics.tap()
        digits.append(digit)
        if digits.count == 4 {
            let pin = digits.map(String.init).joined()
            onApprove(pin)
        }
    }

    private func deleteLastDigit() {
        guard !digits.isEmpty else { return }
        BrandHaptics.tap()
        digits.removeLast()
    }
}

// MARK: - PinKey

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
        .accessibilityIdentifier("emp.pin.key.\(label)")
    }
}
