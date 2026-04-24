#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40 — Look up a gift card by number (code) and optional PIN.
///
/// `GET /api/v1/gift-cards/lookup/:code`
///
/// iPhone: standard sheet with `.medium`/`.large` detents; full-screen search
/// bar at the top so the cashier can tap straight in.
///
/// iPad: centred panel at 520 pt fixed width with a two-column result area
/// (balance card left, action buttons right) once a card is found.
///
/// The server enforces rate limiting on failed lookups; the view surfaces the
/// 429 error with a clear "wait before trying again" message.
struct GiftCardLookupView: View {
    @Environment(\.dismiss) private var dismiss
    let api: APIClient

    // MARK: - State

    enum LookupState: Equatable {
        case idle
        case loading
        case found(GiftCard)
        case failure(String)
    }

    @State private var codeInput: String = ""
    @State private var lookupState: LookupState = .idle

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    phoneLayout
                } else {
                    padLayout
                }
            }
            .navigationTitle("Look Up Gift Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 520)
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        Form {
            searchSection
            resultSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        Form {
            searchSection
            if case .found(let card) = lookupState {
                Section {
                    HStack(alignment: .top, spacing: BrandSpacing.xl) {
                        GiftCardBalanceCard(card: card, prominent: true)
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                            cardDetailRows(card: card)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, BrandSpacing.sm)
                }
            } else {
                resultSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Search section

    private var searchSection: some View {
        Section("Card number or barcode") {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "creditcard.viewfinder")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                TextField("Enter card code", text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .monospaced()
                    .submitLabel(.search)
                    .onSubmit { Task { await performLookup() } }
                    .accessibilityIdentifier("giftCardLookup.codeInput")
                lookupButton
            }
        }
    }

    private var lookupButton: some View {
        Button {
            Task { await performLookup() }
        } label: {
            if lookupState == .loading {
                ProgressView()
            } else {
                Text("Look up")
            }
        }
        .buttonStyle(.bordered)
        .tint(.bizarreOrange)
        .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || lookupState == .loading)
        .accessibilityIdentifier("giftCardLookup.lookup")
    }

    // MARK: - Result section

    @ViewBuilder
    private var resultSection: some View {
        switch lookupState {
        case .idle:
            EmptyView()

        case .loading:
            Section {
                HStack {
                    Spacer()
                    ProgressView("Looking up card…")
                    Spacer()
                }
                .padding(.vertical, BrandSpacing.md)
            }

        case .found(let card):
            Section {
                GiftCardBalanceCard(card: card, prominent: false)
                    .padding(.vertical, BrandSpacing.xs)
            }
            Section("Details") {
                cardDetailRows(card: card)
            }

        case .failure(let msg):
            Section {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("giftCardLookup.error")
            }
        }
    }

    // MARK: - Card detail rows

    @ViewBuilder
    private func cardDetailRows(card: GiftCard) -> some View {
        LabeledContent("Full code") {
            Text(card.code)
                .font(.brandBodyMedium())
                .monospaced()
                .textSelection(.enabled)
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityIdentifier("giftCardLookup.fullCode")

        LabeledContent("Balance") {
            Text(CartMath.formatCents(card.balanceCents))
                .font(.brandTitleSmall())
                .monospacedDigit()
                .foregroundStyle(.bizarreOrange)
        }

        LabeledContent("Status") {
            Text(card.active ? "Active" : "Inactive")
                .font(.brandLabelLarge())
                .foregroundStyle(card.active ? .bizarreSuccess : .bizarreError)
        }

        if let exp = card.expiresAt, !exp.isEmpty {
            LabeledContent("Expires") {
                Text(exp)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    // MARK: - Lookup

    private func performLookup() async {
        let trimmed = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lookupState = .loading
        do {
            let card = try await api.lookupGiftCard(code: trimmed)
            lookupState = .found(card)
        } catch let APITransportError.httpStatus(429, _) {
            lookupState = .failure("Too many lookup attempts. Please wait before trying again.")
        } catch let APITransportError.httpStatus(code, message) {
            let msg = message?.isEmpty == false ? message! : "Card not found"
            lookupState = .failure("Lookup failed (\(code)): \(msg)")
        } catch {
            lookupState = .failure("Lookup failed: \(error.localizedDescription)")
        }
    }
}
#endif
