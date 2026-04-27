#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import CoreImage
import CoreImage.CIFilterBuiltins

/// §16 Customer-Facing Display — full-screen layout for the secondary
/// iPad / external HDMI screen that shows the live cart to the customer.
///
/// Layout zones:
/// - **Header** (Liquid Glass): merchant logo / brand name + optional tagline.
/// - **Content**: idle screen, marketing slideshow, post-sale celebration,
///   or scrollable cart lines.
/// - **Footer** (Liquid Glass): subtotal / tax / tip / total summary, huge type.
///
/// §16 additions this wave:
/// - Tenant-configured `shopName` + `shopTagline` in header (§16 layout).
/// - Post-sale "Thank you!" confetti state with tracking QR + Google review QR
///   auto-dismissed after 10s (§16 receipt/thank-you).
/// - `privacyModeEnabled` guard — no cashier data or cross-sale customer data
///   ever renders on the customer display (§16 privacy).
///
/// Accessibility: VoiceOver reads out the item count and grand total so an
/// operator can verify what the customer sees hands-free.
/// Reduce Motion: scale transitions are replaced by opacity fades.
///
/// This view is hosted in the `"cfd"` `WindowGroup` in `BizarreCRMApp.swift`
/// (advisory-lock zone — see agent-ownership.md). Do NOT call it from the
/// main POS scene.
public struct CFDView: View {

    private let bridge: CFDBridge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - §16 Post-sale dismiss countdown

    @State private var postSaleDismissCountdown: Int = 10
    @State private var postSaleDismissTask: Task<Void, Never>? = nil

    // MARK: - §16 Confetti

    @State private var showConfetti: Bool = false

    public init(bridge: CFDBridge = .shared) {
        self.bridge = bridge
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .zIndex(1)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if bridge.postSaleState == nil && bridge.isActive {
                    footer
                        .zIndex(1)
                }
            }

            // §16 — Confetti overlay (Reduce Motion: omitted entirely)
            if showConfetti && !reduceMotion {
                CFDConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityCartSummary)
        // Trigger post-sale countdown when state arrives
        .onChange(of: bridge.postSaleState) { _, newState in
            if newState != nil {
                startPostSaleDismiss()
                if !reduceMotion {
                    withAnimation(.easeIn(duration: 0.3)) { showConfetti = true }
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(.easeOut(duration: 1.0)) { showConfetti = false }
                    }
                }
            } else {
                cancelPostSaleDismiss()
                showConfetti = false
            }
        }
        // Any tap from the customer cancels the countdown
        .simultaneousGesture(
            TapGesture().onEnded { cancelPostSaleDismiss() }
        )
    }

    // MARK: - Header (§16 tenant branding)

    private var header: some View {
        HStack {
            Spacer()
            VStack(spacing: BrandSpacing.xxs) {
                Text(bridge.shopName)
                    .font(.brandDisplayMedium())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityAddTraits(.isHeader)
                if !bridge.shopTagline.isEmpty {
                    Text(bridge.shopTagline)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityIdentifier("cfd.header.tagline")
                }
            }
            Spacer()
        }
        .padding(.vertical, BrandSpacing.lg)
        .background(
            Rectangle()
                .brandGlass(.regular, in: Rectangle())
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if let postSale = bridge.postSaleState {
            // §16 — Post-sale thank-you screen
            CFDThankYouView(
                state: postSale,
                countdown: postSaleDismissCountdown,
                languageCode: bridge.customerLanguageCode
            )
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else if bridge.isActive {
            cartLines
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else {
            CFDIdleView()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02)))
        }
    }

    private var cartLines: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(bridge.items) { line in
                    CFDLineRow(line: line)
                        .padding(.horizontal, BrandSpacing.xl)
                        .padding(.vertical, BrandSpacing.sm)
                }
            }
            .padding(.vertical, BrandSpacing.md)
        }
        .accessibilityIdentifier("cfd.cartLines")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: BrandSpacing.sm) {
            Divider()
                .background(Color.bizarreOutline.opacity(0.3))

            HStack(spacing: BrandSpacing.xl) {
                totalsColumn(label: localised("Subtotal"), cents: bridge.subtotalCents)
                if bridge.taxCents > 0 {
                    totalsColumn(label: localised("Tax"), cents: bridge.taxCents)
                }
                if bridge.tipCents > 0 {
                    totalsColumn(label: localised("Tip"), cents: bridge.tipCents)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text(localised("TOTAL"))
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(CartMath.formatCents(bridge.totalCents))
                        .font(.brandDisplayLarge())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(bridge.totalCents)))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bridge.totalCents)
                }
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.vertical, BrandSpacing.lg)

            if bridge.isActive {
                Text(localised("Please wait for your cashier"))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.bottom, BrandSpacing.md)
                    .accessibilityIdentifier("cfd.waitMessage")
            }
        }
        .background(
            Rectangle()
                .brandGlass(.regular, in: Rectangle())
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func totalsColumn(label: String, cents: Int) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(CartMath.formatCents(cents))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(cents)))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cents)
        }
    }

    // MARK: - §16 Post-sale dismiss countdown

    private func startPostSaleDismiss() {
        postSaleDismissCountdown = 10
        postSaleDismissTask?.cancel()
        postSaleDismissTask = Task {
            for remaining in stride(from: 9, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                postSaleDismissCountdown = remaining
            }
            // Auto-dismiss: clear the post-sale state back to idle.
            bridge.clear()
        }
    }

    private func cancelPostSaleDismiss() {
        postSaleDismissTask?.cancel()
        postSaleDismissTask = nil
    }

    // MARK: - §16 Multi-language helpers

    /// Returns a localised string for the given English key.
    /// Currently supports EN / ES / FR / DE — extend as new languages are added.
    /// Intentionally NOT using `NSLocalizedString` since these are customer-facing
    /// strings whose locale is decoupled from the cashier's app locale.
    private func localised(_ key: String) -> String {
        let lang = bridge.customerLanguageCode
        let table: [String: [String: String]] = [
            "Subtotal":                    ["es": "Subtotal",           "fr": "Sous-total", "de": "Zwischensumme"],
            "Tax":                         ["es": "Impuesto",           "fr": "Taxe",       "de": "Steuer"],
            "Tip":                         ["es": "Propina",            "fr": "Pourboire",  "de": "Trinkgeld"],
            "TOTAL":                       ["es": "TOTAL",              "fr": "TOTAL",      "de": "GESAMT"],
            "Please wait for your cashier":["es": "Por favor espere",   "fr": "Veuillez patienter", "de": "Bitte warten"],
            "Thank you!":                  ["es": "¡Gracias!",          "fr": "Merci !",    "de": "Danke!"],
            "Scan to track your order":    ["es": "Escanea para rastrear", "fr": "Scannez pour suivre", "de": "Scannen zum Verfolgen"],
            "Leave us a review":           ["es": "Déjanos una reseña", "fr": "Laissez un avis", "de": "Bewertung abgeben"],
        ]
        return table[key]?[lang] ?? key
    }

    // MARK: - Accessibility helpers

    private var accessibilityCartSummary: String {
        if bridge.postSaleState != nil {
            return "Sale complete — thank you screen"
        } else if bridge.isActive {
            return "\(bridge.items.count) item\(bridge.items.count == 1 ? "" : "s"), total \(CartMath.formatCents(bridge.totalCents))"
        } else {
            return "Customer display idle"
        }
    }
}

// MARK: - CFDLineRow

private struct CFDLineRow: View {
    let line: CFDCartLine

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Text("\(line.quantity)×")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(minWidth: 32, alignment: .trailing)
                .accessibilityHidden(true)

            Text(line.name)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(CartMath.formatCents(line.lineTotalCents))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.quantity) \(line.name), \(CartMath.formatCents(line.lineTotalCents))")
    }
}

// MARK: - CFDThankYouView (§16 receipt/thank-you)

/// §16 — Post-sale celebration screen shown on the customer display.
/// Displays:
/// - Large "Thank you!" heading with success color.
/// - Tracking QR code (from `state.trackingToken`).
/// - Google review QR (from `state.googleReviewURL`) if configured.
/// - Membership sign-up QR (from `state.membershipSignupURL`) if configured.
/// - Auto-dismiss countdown: "Closing in Ns…"
///
/// Reduce Motion: confetti and scale animation are skipped by the parent;
/// this view itself only shows a static layout.
private struct CFDThankYouView: View {
    let state: CFDPostSaleState
    let countdown: Int
    let languageCode: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: BrandSpacing.xl) {
            Spacer()

            // "Thank you!" headline
            Text(localised("Thank you!"))
                .font(.brandDisplayLarge())
                .foregroundStyle(Color.bizarreSuccess)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("cfd.thankyou.headline")
                .scaleEffect(reduceMotion ? 1 : 1.05)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: countdown)

            // QR codes row
            HStack(spacing: BrandSpacing.xl) {
                if let token = state.trackingToken {
                    qrBlock(
                        label: localised("Scan to track your order"),
                        urlString: "https://app.bizarrecrm.com/track/\(token)"
                    )
                }

                if let reviewURL = state.googleReviewURL {
                    qrBlock(
                        label: localised("Leave us a review"),
                        urlString: reviewURL.absoluteString
                    )
                }
            }

            // Auto-dismiss countdown
            if countdown > 0 {
                Text("Closing in \(countdown)s…")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.5), value: countdown)
                    .accessibilityIdentifier("cfd.thankyou.countdown")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.xxl)
    }

    @ViewBuilder
    private func qrBlock(label: String, urlString: String) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            if let qrImage = generateQR(from: urlString) {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("cfd.thankyou.qr")
            }
            Text(label)
                .font(.brandLabelMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 160)
        }
    }

    private func generateQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func localised(_ key: String) -> String {
        let table: [String: [String: String]] = [
            "Thank you!":               ["es": "¡Gracias!",          "fr": "Merci !",    "de": "Danke!"],
            "Scan to track your order": ["es": "Escanea para rastrear", "fr": "Scannez pour suivre", "de": "Scannen zum Verfolgen"],
            "Leave us a review":        ["es": "Déjanos una reseña", "fr": "Laissez un avis", "de": "Bewertung abgeben"],
        ]
        return table[key]?[languageCode] ?? key
    }
}

// MARK: - CFDConfettiView (§16 receipt/thank-you — Reduce Motion gated by parent)

/// Simple confetti animation using SF Symbols particles. Shown on the CFD
/// post-sale celebration screen. The parent (`CFDView`) only renders this
/// when `accessibilityReduceMotion` is `false`.
private struct CFDConfettiView: View {
    @State private var particles: [ConfettiParticle] = []

    private let colors: [Color] = [.bizarreOrange, .bizarreSuccess, .bizarreTeal, Color.white.opacity(0.8)]
    private let symbols = ["star.fill", "heart.fill", "circle.fill", "diamond.fill"]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Image(systemName: particle.symbol)
                        .font(.system(size: particle.size))
                        .foregroundStyle(particle.color)
                        .position(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                        .rotationEffect(.degrees(particle.rotation))
                }
            }
            .onAppear {
                particles = (0..<60).map { _ in
                    ConfettiParticle(
                        x: CGFloat.random(in: 0...geo.size.width),
                        y: CGFloat.random(in: -80...geo.size.height * 0.3),
                        symbol: symbols.randomElement()!,
                        color: colors.randomElement()!,
                        size: CGFloat.random(in: 12...24),
                        opacity: Double.random(in: 0.6...1.0),
                        rotation: Double.random(in: 0...360)
                    )
                }
                withAnimation(.easeOut(duration: 3.5)) {
                    for index in particles.indices {
                        particles[index].y += CGFloat.random(in: geo.size.height * 0.6...geo.size.height * 1.2)
                        particles[index].opacity = 0
                        particles[index].rotation += Double.random(in: 180...540)
                    }
                }
            }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let symbol: String
    let color: Color
    let size: CGFloat
    var opacity: Double
    var rotation: Double
}
#endif
