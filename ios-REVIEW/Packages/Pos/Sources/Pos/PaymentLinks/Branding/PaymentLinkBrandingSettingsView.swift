#if canImport(UIKit)
import SwiftUI
import WebKit
import Core
import DesignSystem
import Networking

// MARK: - §41.2 Branding Settings

/// Admin screen: customize logo URL, colors, footer text, and terms for the
/// public pay page. A WKWebView preview renders a sample page using server HTML.
/// iPhone: form + fullscreen sheet preview.
/// iPad: NavigationSplitView — form on left, live preview on right.
public struct PaymentLinkBrandingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PaymentLinkBrandingViewModel
    @State private var showPreview: Bool = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: PaymentLinkBrandingViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Payment page branding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await vm.load() }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "An error occurred.")
        }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            form
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                PaymentLinkBrandingPreviewView(previewURL: vm.previewURL)
                    .navigationTitle("Preview")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPreview = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
        } detail: {
            PaymentLinkBrandingPreviewView(previewURL: vm.previewURL)
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section("Logo") {
                TextField("Logo URL", text: $vm.logoUrl)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Logo URL")
            }

            Section("Colors") {
                HStack {
                    Text("Primary color")
                    Spacer()
                    TextField("#FF6B00", text: $vm.primaryColor)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Primary color hex")
                    if let c = Color(hex: vm.primaryColor) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(c)
                            .frame(width: 24, height: 24)
                    }
                }
                HStack {
                    Text("Secondary color")
                    Spacer()
                    TextField("#333333", text: $vm.secondaryColor)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Secondary color hex")
                    if let c = Color(hex: vm.secondaryColor) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(c)
                            .frame(width: 24, height: 24)
                    }
                }
            }

            Section("Footer") {
                TextField("Footer text", text: $vm.footerText, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityLabel("Footer text")
            }

            Section("Terms") {
                TextField("Terms & conditions URL or text", text: $vm.terms, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityLabel("Terms and conditions")
            }

            if Platform.isCompact {
                Section {
                    Button {
                        showPreview = true
                    } label: {
                        Label("Preview pay page", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.bizarreOrange)
                }
            }

            Section {
                Button {
                    BrandHaptics.tap()
                    Task { await vm.save() }
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        if vm.isSaving { ProgressView() }
                        Text(vm.isSaving ? "Saving…" : "Save branding")
                            .font(.brandTitleSmall())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .controlSize(.large)
                .disabled(vm.isSaving)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("branding.saveButton")
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }
}

// MARK: - Preview view (WKWebView)

/// Renders the server-generated sample pay page HTML in a WKWebView.
/// Falls back to a placeholder when the URL is unavailable.
struct PaymentLinkBrandingPreviewView: View {
    let previewURL: URL?

    var body: some View {
        if let url = previewURL {
            BrandingWebPreview(url: url)
                .ignoresSafeArea()
        } else {
            ContentUnavailableView(
                "No preview available",
                systemImage: "globe",
                description: Text("Enter a valid server URL to see the live preview.")
            )
        }
    }
}

/// `UIViewRepresentable` wrapper around `WKWebView`.
struct BrandingWebPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let wk = WKWebView(frame: .zero, configuration: config)
        wk.load(URLRequest(url: url))
        return wk
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PaymentLinkBrandingViewModel {
    public var logoUrl: String = ""
    public var primaryColor: String = ""
    public var secondaryColor: String = ""
    public var footerText: String = ""
    public var terms: String = ""

    public private(set) var isLoading: Bool = false
    public private(set) var isSaving: Bool = false
    public var showError: Bool = false
    public private(set) var errorMessage: String?

    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    /// URL used for the WKWebView preview — points at the server's sample pay page.
    public var previewURL: URL? {
        Task { await api.currentBaseURL() }
        // Synchronous approximation: use the stored base URL + preview path.
        // In practice the view calls `task { await vm.load() }` first which
        // hydrates `_cachedBase`.
        guard let base = _cachedBase else { return nil }
        return base.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("pay/preview")
    }

    private var _cachedBase: URL?

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        _cachedBase = await api.currentBaseURL()
        do {
            let branding = try await api.getPaymentLinkBranding()
            apply(branding)
        } catch {
            // First load may 404 if tenant hasn't configured branding yet — fine.
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        let patch = PaymentLinkBrandingPatch(from: current)
        do {
            let updated = try await api.updatePaymentLinkBranding(patch)
            apply(updated)
            BrandHaptics.success()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save branding."
            showError = true
        }
    }

    // MARK: - Helpers

    private var current: PaymentLinkBranding {
        PaymentLinkBranding(
            logoUrl: logoUrl.isEmpty ? nil : logoUrl,
            primaryColor: primaryColor.isEmpty ? nil : primaryColor,
            secondaryColor: secondaryColor.isEmpty ? nil : secondaryColor,
            footerText: footerText.isEmpty ? nil : footerText,
            terms: terms.isEmpty ? nil : terms
        )
    }

    private func apply(_ b: PaymentLinkBranding) {
        logoUrl = b.logoUrl ?? ""
        primaryColor = b.primaryColor ?? ""
        secondaryColor = b.secondaryColor ?? ""
        footerText = b.footerText ?? ""
        terms = b.terms ?? ""
    }
}

// MARK: - Color(hex:) helper (local, non-exported)

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
#endif
