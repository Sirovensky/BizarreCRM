#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

/// §39 / §16 — end-of-shift close sheet with live color-coded variance badge
/// and polished shift summary header.
///
/// ## Register-close summary polish (§16)
/// - Shift duration chip in the header (e.g. "4 h 22 min").
/// - Opening float + session ID tile in the "Shift" section.
/// - Variance card now includes a human-readable band description
///   ("On target", "Minor variance", "Investigate required") alongside the
///   signed amount so cashiers understand the severity at a glance.
/// - Error banner uses `.bizarreError` surface tint + SF Symbol for
///   faster visual parsing.
/// - Red-band variance (> ±$5) blocks the Close CTA until notes are typed.
public struct CloseRegisterSheet: View {
    public let session: CashSessionRecord
    public let expectedCents: Int
    public let closedBy: Int64
    public let onClosed: (CashSessionRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var countedText: String = ""
    @State private var notes: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    // §16.10 — Blind-count mode: cashier counts without seeing the expected
    // total. Expected total is revealed only after the cashier submits.
    @State private var blindCountMode: Bool = false
    @State private var blindCountRevealed: Bool = false

    public init(session: CashSessionRecord, expectedCents: Int, closedBy: Int64, onClosed: @escaping (CashSessionRecord) -> Void) {
        self.session = session
        self.expectedCents = expectedCents
        self.closedBy = closedBy
        self.onClosed = onClosed
    }

    public var body: some View {
        NavigationStack {
            Form {
                // §16 — Shift summary header card (polished)
                shiftSummaryHeader

                // §16.10 — Blind count toggle (loss-prevention mode)
                Section {
                    Toggle(isOn: $blindCountMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blind count")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Cashier counts without seeing expected total")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("pos.closeRegister.blindCount")
                    .onChange(of: blindCountMode) { _, _ in
                        // Reset reveal state when toggled
                        blindCountRevealed = false
                    }
                }

                Section("Shift") {
                    row("Opened", Self.format(date: session.openedAt))
                        .accessibilityIdentifier("pos.closeRegister.opened")
                    row("Duration", shiftDuration)
                        .accessibilityIdentifier("pos.closeRegister.duration")
                    row("Opening float", CartMath.formatCents(session.openingFloat))
                        .accessibilityIdentifier("pos.closeRegister.float")
                    if !blindCountMode || blindCountRevealed {
                        row("Expected in drawer", CartMath.formatCents(expectedCents))
                            .accessibilityIdentifier("pos.closeRegister.expected")
                    } else {
                        HStack {
                            Text("Expected in drawer")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Text("Hidden — blind count mode")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .italic()
                        }
                        .accessibilityLabel("Expected total hidden. Blind count mode active.")
                    }
                }
                Section("Count") {
                    HStack(spacing: BrandSpacing.sm) {
                        Text("Counted cash").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                        Spacer(minLength: BrandSpacing.md)
                        Text("$").font(.brandBodyLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                        TextField("0.00", text: $countedText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .accessibilityIdentifier("pos.closeRegister.counted")
                    }
                }
                if blindCountMode && !blindCountRevealed {
                    Section {
                        Button {
                            guard countedCents > 0 else { return }
                            blindCountRevealed = true
                        } label: {
                            HStack {
                                Image(systemName: "eye.fill")
                                    .accessibilityHidden(true)
                                Text(countedCents > 0
                                     ? "Reveal expected total"
                                     : "Enter counted amount first")
                                    .font(.brandBodyMedium())
                            }
                            .foregroundStyle(countedCents > 0 ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                        }
                        .disabled(countedCents == 0)
                        .accessibilityIdentifier("pos.closeRegister.revealExpected")
                    }
                } else {
                    Section { varianceBadge.accessibilityIdentifier("pos.closeRegister.variance") }
                }
                Section {
                    TextField(notesPlaceholder, text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("pos.closeRegister.notes")
                } header: {
                    Text(notesHeader)
                } footer: {
                    if band == .red {
                        Text("Required when variance is greater than $5.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }
                if let err = errorMessage {
                    Section { Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Close register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Closing…" : "Close") { Task { await commit() } }
                        .disabled(isSubmitting || !canSubmit)
                        .accessibilityIdentifier("pos.closeRegister.cta")
                }
            }
        }
    }

    private var countedCents: Int {
        let trimmed = countedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value >= 0 else { return 0 }
        return CartMath.toCents(value)
    }
    private var varianceCents: Int { countedCents - expectedCents }
    private var band: CashVariance.Band { CashVariance.band(cents: varianceCents) }
    private var canSubmit: Bool {
        let trimmed = countedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return CashVariance.canCommit(varianceCents: varianceCents, notes: notes)
    }
    private var notesHeader: String { band == .red ? "Notes (required)" : "Notes" }
    private var notesPlaceholder: String {
        band == .red ? "Explain the variance (e.g. till skim, manager drop)" : "Optional — short context for the Z-report"
    }

    // MARK: - §16 Register-close summary polish

    /// Shift duration in human-readable form, e.g. "4 h 22 min" or "38 min".
    private var shiftDuration: String {
        let elapsed = Date().timeIntervalSince(session.openedAt)
        let totalMinutes = Int(elapsed / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        } else {
            return "\(max(minutes, 1)) min"
        }
    }

    /// Summary header card shown above the form sections. Surfaces the
    /// shift interval + opening float at a glance without scrolling.
    @ViewBuilder
    private var shiftSummaryHeader: some View {
        Section {
            HStack(alignment: .center, spacing: BrandSpacing.base) {
                // Clock icon
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Closing shift")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(shiftDuration)
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    Text("Opened \(Self.format(date: session.openedAt))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Spacer(minLength: BrandSpacing.sm)

                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text("Float")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(CartMath.formatCents(session.openingFloat))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    if let sid = session.id {
                        Text("#\(sid)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.6))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, BrandSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Closing shift. Duration \(shiftDuration). Float \(CartMath.formatCents(session.openingFloat))."
        )
        .accessibilityIdentifier("pos.closeRegister.summaryHeader")
    }

    // MARK: - Variance badge (polished)

    private var varianceBadge: some View {
        HStack(spacing: BrandSpacing.sm) {
            // Status dot
            Circle().fill(band.color).frame(width: 10, height: 10).accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Variance").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(Self.formatSigned(cents: varianceCents))
                    .font(.brandTitleLarge())
                    .foregroundStyle(band.color)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: varianceCents < 0))
                    .animation(.easeInOut(duration: 0.2), value: varianceCents)
                // Human-readable severity description (§16 polish)
                Text(bandDescription)
                    .font(.brandLabelSmall())
                    .foregroundStyle(band.color.opacity(0.85))
            }

            Spacer(minLength: 0)

            // Band badge pill
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: bandSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(band.shortLabel)
                    .font(.brandLabelLarge())
            }
            .foregroundStyle(band.color)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs + 2)
            .background(band.color.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Variance \(Self.formatSigned(cents: varianceCents)). \(bandDescription). \(band.shortLabel).")
    }

    /// Descriptive phrase matching the variance band.
    private var bandDescription: String {
        switch band {
        case .green: return varianceCents == 0 ? "Exact match" : "On target"
        case .amber: return "Minor variance"
        case .red: return "Investigate required"
        }
    }

    /// Icon matching the variance band for the badge pill.
    private var bandSystemImage: String {
        switch band {
        case .green: return "checkmark.circle.fill"
        case .amber: return "exclamationmark.triangle.fill"
        case .red: return "xmark.circle.fill"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(label).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
            Spacer(minLength: BrandSpacing.md)
            Text(value).font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
        }
    }

    private func commit() async {
        guard !isSubmitting else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else {
            errorMessage = "Enter the counted cash and any required notes."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            let closed = try await CashRegisterStore.shared.closeSession(
                countedCash: countedCents,
                expectedCash: expectedCents,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                closedBy: closedBy
            )
            BrandHaptics.success()
            AppLog.pos.info("POS drawer closed: session=\(closed.id ?? -1) variance=\(varianceCents)")
            onClosed(closed)
            dismiss()
        } catch CashRegisterError.noOpenSession {
            errorMessage = "No open session — reopen the register before closing."
        } catch {
            AppLog.pos.error("POS drawer close failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public static func formatSigned(cents: Int) -> String {
        let abs = CartMath.formatCents(Swift.abs(cents))
        if cents > 0 { return "+\(abs)" }
        if cents < 0 { return "-\(abs)" }
        return abs
    }
    private static func format(date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}
#endif
