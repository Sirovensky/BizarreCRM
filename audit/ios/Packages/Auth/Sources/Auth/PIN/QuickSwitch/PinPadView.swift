import SwiftUI
import Core
import DesignSystem

// MARK: - PinPadViewModel

@MainActor
@Observable
final class PinPadViewModel {
    // MARK: - State

    var digits: [Int] = []
    var isShuffled: Bool = false
    var errorMessage: String? = nil
    var successFeedback: Bool = false

    let pinLength: Int

    /// Current scrambled order of digit buttons (0–9).
    private(set) var digitOrder: [Int] = Array(0...9)

    // MARK: - Init

    init(pinLength: Int = 4) {
        self.pinLength = pinLength
    }

    // MARK: - Computed

    var currentPin: String {
        digits.map(String.init).joined()
    }

    var isFull: Bool { digits.count >= pinLength }

    // MARK: - Actions

    func toggle(shuffle: Bool) {
        isShuffled = shuffle
        if shuffle {
            digitOrder = Array(0...9).shuffled()
        } else {
            digitOrder = Array(0...9)
        }
    }

    func append(digit: Int) {
        guard digits.count < pinLength else { return }
        errorMessage = nil
        digits.append(digit)
    }

    func deleteLastDigit() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    func clear() {
        digits = []
        errorMessage = nil
    }

    func showError(_ message: String) {
        clear()
        errorMessage = message
    }
}

// MARK: - PinPadView

/// A 4-digit PIN entry pad with an optional shuffle mode (anti-shoulder-surf).
///
/// **iPhone**: full-screen, centred vertically.
/// **iPad**: inset card (max width 360 pt), centred in the available space.
///
/// Usage:
/// ```swift
/// PinPadView(pinLength: 4) { pin in
///     await service.attempt(pin: pin)
/// }
/// ```
public struct PinPadView: View {
    // MARK: - Properties

    private let onSubmit: @MainActor (String) async -> Void
    private let title: String
    private let subtitle: String?

    @State private var vm: PinPadViewModel

    // MARK: - Init

    public init(
        pinLength: Int = 4,
        title: String = "Enter PIN",
        subtitle: String? = nil,
        onSubmit: @MainActor @escaping (String) async -> Void
    ) {
        self.onSubmit = onSubmit
        self.title = title
        self.subtitle = subtitle
        _vm = State(initialValue: PinPadViewModel(pinLength: pinLength))
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                iPadLayout
            }
        }
        .onChange(of: vm.isFull) { _, full in
            if full {
                Task { await submit() }
            }
        }
    }

    // MARK: - Layout variants

    @ViewBuilder
    private var phoneLayout: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            headerSection
            dotsRow
            padGrid
            shuffleToggle
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var iPadLayout: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            headerSection
            dotsRow
            padGrid
            shuffleToggle
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: 360)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(.brandBodyLarge())
                .foregroundStyle(.primary)

            if let sub = subtitle {
                Text(sub)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .accessibilityLabel("Error: \(err)")
            }
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.snappy), value: vm.errorMessage)
    }

    /// Row of filled / unfilled dots representing entered digits.
    @ViewBuilder
    private var dotsRow: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            ForEach(0..<vm.pinLength, id: \.self) { i in
                Circle()
                    .fill(i < vm.digits.count ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .scaleEffect(i == vm.digits.count - 1 ? 1.15 : 1.0)
                    .animation(
                        .spring(response: 0.25, dampingFraction: 0.7),
                        value: vm.digits.count
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.digits.count) of \(vm.pinLength) digits entered")
    }

    /// 3×4 digit grid (1-9 top three rows, shuffle / 0 / delete bottom row).
    @ViewBuilder
    private var padGrid: some View {
        let ordered = vm.isShuffled ? vm.digitOrder : Array(0...9)
        // Digits 1–9 occupy the first three rows; row 4 is: shuffle | 0 | delete.
        VStack(spacing: DesignTokens.Spacing.md) {
            ForEach(0..<3) { row in
                HStack(spacing: DesignTokens.Spacing.lg) {
                    ForEach(0..<3) { col in
                        let idx = row * 3 + col
                        // map idx 0..<9 → digits 1..9 in order
                        let digit = orderedDigit(ordered: ordered, index: idx)
                        digitButton(digit: digit)
                    }
                }
            }
            // Bottom row
            HStack(spacing: DesignTokens.Spacing.lg) {
                // Left: shuffle (anti-shoulder-surf)
                shuffleButton

                // Centre: 0
                digitButton(digit: orderedZero(ordered: ordered))

                // Right: delete
                deleteButton
            }
        }
    }

    @ViewBuilder
    private func digitButton(digit: Int) -> some View {
        Button {
            vm.append(digit: digit)
            triggerHaptic()
        } label: {
            Text(String(digit))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(DigitButtonStyle())
        .accessibilityLabel(String(digit))
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button {
            vm.deleteLastDigit()
            triggerHaptic()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(DigitButtonStyle())
        .accessibilityLabel("Delete last digit")
        .disabled(vm.digits.isEmpty)
    }

    @ViewBuilder
    private var shuffleButton: some View {
        Button {
            vm.toggle(shuffle: !vm.isShuffled)
        } label: {
            Image(systemName: vm.isShuffled ? "eye.slash" : "eye")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(DigitButtonStyle())
        .accessibilityLabel(vm.isShuffled ? "Disable shuffled layout" : "Enable shuffled layout (anti-shoulder-surf)")
    }

    @ViewBuilder
    private var shuffleToggle: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "shuffle")
                .font(.brandLabelSmall())
            Text("Shuffle keys")
                .font(.brandLabelSmall())
        }
        .foregroundStyle(vm.isShuffled ? Color.accentColor : Color.secondary)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(shuffle: !vm.isShuffled) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(vm.isShuffled ? "Shuffle mode on" : "Shuffle mode off — tap to enable")
    }

    // MARK: - Helpers

    /// Returns the digit at `index` in the 1–9 range from the ordered array.
    /// When shuffled, `ordered` is [0…9] shuffled; we pick the non-zero
    /// elements for positions 0–8 and the zero for the bottom-centre.
    private func orderedDigit(ordered: [Int], index: Int) -> Int {
        let nonZero = ordered.filter { $0 != 0 }
        guard index < nonZero.count else { return index + 1 }
        return nonZero[index]
    }

    private func orderedZero(ordered: [Int]) -> Int {
        // Zero is always in bottom-centre regardless of shuffle.
        return 0
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        if Platform.supportsHaptics {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
        }
        #endif
    }

    private func submit() async {
        let pin = vm.currentPin
        await onSubmit(pin)
    }
}

// MARK: - DigitButtonStyle

private struct DigitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brandGlass(.regular, in: Circle(), interactive: true)
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                .spring(response: 0.20, dampingFraction: 0.75),
                value: configuration.isPressed
            )
    }
}

