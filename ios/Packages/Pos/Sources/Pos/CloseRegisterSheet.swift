#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

/// §39 — end-of-shift close sheet with live color-coded variance badge.
/// Red-band variance (> ±$5) blocks the Close CTA until notes are typed.
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
                            guard amountCents > 0 else { return }
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

    private var varianceBadge: some View {
        HStack(spacing: BrandSpacing.sm) {
            Circle().fill(band.color).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Variance").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(Self.formatSigned(cents: varianceCents))
                    .font(.brandTitleLarge())
                    .foregroundStyle(band.color)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(band.shortLabel).font(.brandLabelLarge()).foregroundStyle(band.color)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Variance \(Self.formatSigned(cents: varianceCents)). \(band.shortLabel).")
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
