#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40 — Issue a new gift card (admin/manager only).
///
/// `POST /api/v1/gift-cards`
///
/// iPhone: full-sheet with `.medium`/`.large` detents.
/// iPad: centred panel at 560 pt fixed width, `.medium` detent only.
///
/// Liquid Glass on navigation chrome per `ios/CLAUDE.md`.
struct GiftCardIssueView: View {
    @Environment(\.dismiss) private var dismiss
    let api: APIClient

    @State private var viewModel: GiftCardIssueViewModel

    init(api: APIClient) {
        self.api = api
        _viewModel = State(wrappedValue: GiftCardIssueViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Issue Gift Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 560)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if case .issued(let code, let balanceCents) = viewModel.state {
            successView(code: code, balanceCents: balanceCents)
        } else {
            issueForm
        }
    }

    // MARK: - Form

    private var issueForm: some View {
        Form {
            amountSection
            recipientSection
            optionsSection

            if let err = viewModel.validationError, !viewModel.amountInput.isEmpty {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
            }
            if case .failure(let msg) = viewModel.state {
                Section {
                    Text(msg)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
            }
            issueButtonSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Amount section

    private var amountSection: some View {
        Section("Amount") {
            HStack(spacing: BrandSpacing.xs) {
                Text("$")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                TextField("Cents (e.g. 5000 = $50.00)", text: $viewModel.amountInput)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .accessibilityIdentifier("giftCardIssue.amount")
            }
            if viewModel.amountCents > 0 {
                HStack {
                    Text("Value")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(CartMath.formatCents(viewModel.amountCents))
                        .font(.brandTitleMedium())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOrange)
                }
            }
        }
    }

    // MARK: - Recipient section

    private var recipientSection: some View {
        Section("Recipient (optional)") {
            TextField("Name", text: $viewModel.recipientName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("giftCardIssue.recipientName")
            TextField("Email", text: $viewModel.recipientEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("giftCardIssue.recipientEmail")
        }
    }

    // MARK: - Options section

    private var optionsSection: some View {
        Section("Options") {
            // BUGHUNT-2026-05-18: was a yyyy-MM-dd free-text TextField.
            // Locale-sensitive typos (`mm/dd/yyyy`) would fail server-side
            // silently and ship a card with no expiry. Toggle + DatePicker
            // preserves the optional semantics while keeping the wire format
            // pinned to en_US_POSIX UTC.
            Toggle("Set expiry date", isOn: Binding(
                get: { !viewModel.expiresAtInput.isEmpty },
                set: { newValue in
                    if newValue && viewModel.expiresAtInput.isEmpty {
                        // Default to 1 year out, a reasonable industry default.
                        let defaultDate = Date().addingTimeInterval(60 * 60 * 24 * 365)
                        viewModel.expiresAtInput = Self.formatExpiry(defaultDate)
                    } else if !newValue {
                        viewModel.expiresAtInput = ""
                    }
                }
            ))
            .accessibilityIdentifier("giftCardIssue.hasExpiry")
            if !viewModel.expiresAtInput.isEmpty {
                DatePicker(
                    "Expiry date",
                    selection: Binding(
                        get: { Self.parseExpiry(viewModel.expiresAtInput) ?? Date().addingTimeInterval(60 * 60 * 24 * 365) },
                        set: { viewModel.expiresAtInput = Self.formatExpiry($0) }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .accessibilityIdentifier("giftCardIssue.expiresAt")
            }
            TextField("Notes", text: $viewModel.notes, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("giftCardIssue.notes")
        }
    }

    /// Adapter helpers for the expiry `DatePicker`. Pinned to en_US_POSIX UTC
    /// so wire format ("yyyy-MM-dd") matches regardless of device locale.
    private static let expiryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    fileprivate static func parseExpiry(_ raw: String) -> Date? {
        expiryFormatter.date(from: raw)
    }

    fileprivate static func formatExpiry(_ date: Date) -> String {
        expiryFormatter.string(from: date)
    }

    // MARK: - Issue button

    private var issueButtonSection: some View {
        Section {
            Button {
                Task { await viewModel.issue() }
            } label: {
                HStack {
                    if case .issuing = viewModel.state {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "creditcard.fill")
                    }
                    Text("Issue Gift Card")
                        .font(.brandTitleSmall())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!viewModel.canIssue)
            .accessibilityIdentifier("giftCardIssue.issue")
        }
    }

    // MARK: - Success

    private func successView(code: String, balanceCents: Int) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreSuccess)
                .padding(.top, BrandSpacing.xl)

            VStack(spacing: BrandSpacing.sm) {
                Text("Gift Card Issued")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)

                Text(CartMath.formatCents(balanceCents))
                    .font(.brandTitleLarge())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOrange)
            }

            // Code is returned exactly once — surface it prominently.
            VStack(spacing: BrandSpacing.xs) {
                Text("Card Code")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(code)
                    .font(.brandTitleMedium())
                    .monospaced()
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            .padding(BrandSpacing.base)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))

            if Platform.isCompact {
                // iPhone: show hint to record the code.
                Text("Record this code now — it won't be shown again.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }

            Spacer()

            VStack(spacing: BrandSpacing.sm) {
                Button("Issue Another") {
                    viewModel.reset()
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("giftCardIssue.issueAnother")

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("giftCardIssue.done")
            }
            .padding(.bottom, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gift card issued. Code \(code). Balance \(CartMath.formatCents(balanceCents)).")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
    }
}
#endif
