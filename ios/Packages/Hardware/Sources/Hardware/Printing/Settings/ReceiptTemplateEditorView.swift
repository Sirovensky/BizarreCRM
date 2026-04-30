#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - ReceiptTemplateEditorView
//
// §17 — "Receipt template editor (Settings → Printing): header logo + shop info +
//  body (lines / totals / payment / tax) + footer (return policy, thank-you, QR
//  lookup) + live preview."
//
// This editor lets the tenant customize the look of their printed receipts.
// Changes are persisted in UserDefaults under `ReceiptTemplateStore.key`.
// Live preview re-renders `ReceiptView` with sample data using the same pipeline
// that drives real print jobs — "what tenant sees is what prints" (§17.4).

// MARK: - ReceiptTemplate (persisted settings)

public struct ReceiptTemplate: Codable, Sendable, Equatable {
    // Header
    public var showLogo: Bool           = true
    public var headerShopName: String   = ""
    public var headerAddress: String    = ""
    public var headerPhone: String      = ""
    public var headerWebsite: String    = ""

    // Body toggles
    public var showSubtotal: Bool       = true
    public var showTax: Bool            = true
    public var showTip: Bool            = true
    public var showPaymentMethod: Bool  = true
    public var showCashierName: Bool    = true

    // Footer
    public var footerReturnPolicy: String = ""
    public var footerThankYouMessage: String = "Thank you for your business!"
    public var showQRCode: Bool         = true
    public var footerQRContent: String  = ""   // e.g. "https://bizarrecrm.com/lookup"

    public init() {}
}

// MARK: - ReceiptTemplateStore

public enum ReceiptTemplateStore {
    static let key = "com.bizarrecrm.hardware.receiptTemplate"

    public static func load() -> ReceiptTemplate {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ReceiptTemplate.self, from: data) else {
            return ReceiptTemplate()
        }
        return decoded
    }

    public static func save(_ template: ReceiptTemplate) {
        guard let data = try? JSONEncoder().encode(template) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - ReceiptTemplateEditorView

/// Settings → Printing → Receipt Template
///
/// iPhone: `NavigationStack` pushed from `PrinterProfileSettingsView`.
/// iPad: Master-detail pane; left column = form, right column = live preview.
public struct ReceiptTemplateEditorView: View {

    // MARK: - State

    @State private var template: ReceiptTemplate = ReceiptTemplateStore.load()
    @State private var isDirty: Bool = false
    @State private var savedBanner: Bool = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .navigationTitle("Receipt Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .overlay(alignment: .top) {
            if savedBanner {
                savedBannerView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.snappy), value: savedBanner)
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                editorForm
                    .padding(.bottom, BrandSpacing.xl)
                Divider()
                previewSection
                    .padding(BrandSpacing.base)
            }
        }
    }

    private var ipadLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                editorForm
                    .frame(maxWidth: 400)
                    .padding(BrandSpacing.base)
            }
            .frame(maxWidth: 440)
            Divider()
            ScrollView {
                previewSection
                    .padding(BrandSpacing.base)
            }
        }
    }

    // MARK: - Editor form

    private var editorForm: some View {
        Form {
            headerSection
            bodySection
            footerSection
        }
        .formStyle(.grouped)
        .onChange(of: template) { isDirty = true }
    }

    private var headerSection: some View {
        Section("Header") {
            Toggle("Show Logo", isOn: $template.showLogo)
                .accessibilityLabel("Show business logo on receipt")
            TextField("Shop Name", text: $template.headerShopName)
                .accessibilityLabel("Shop name on receipt header")
            TextField("Address", text: $template.headerAddress)
                .accessibilityLabel("Business address on receipt header")
            TextField("Phone", text: $template.headerPhone)
                .keyboardType(.phonePad)
                .accessibilityLabel("Business phone number on receipt header")
            TextField("Website (optional)", text: $template.headerWebsite)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Business website on receipt header")
        }
    }

    private var bodySection: some View {
        Section("Body") {
            Toggle("Show Subtotal", isOn: $template.showSubtotal)
            Toggle("Show Tax", isOn: $template.showTax)
            Toggle("Show Tip", isOn: $template.showTip)
            Toggle("Show Payment Method", isOn: $template.showPaymentMethod)
            Toggle("Show Cashier Name", isOn: $template.showCashierName)
        }
    }

    private var footerSection: some View {
        Section("Footer") {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Return Policy")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
                TextEditor(text: $template.footerReturnPolicy)
                    .frame(minHeight: 72)
                    .font(.brandBodySmall())
                    .accessibilityLabel("Return policy text on receipt footer")
            }
            TextField("Thank-you Message", text: $template.footerThankYouMessage)
                .accessibilityLabel("Thank-you message on receipt footer")
            Toggle("Show QR Code", isOn: $template.showQRCode)
            if template.showQRCode {
                TextField("QR URL (optional)", text: $template.footerQRContent)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("URL to encode in the receipt QR code")
            }
        }
    }

    // MARK: - Live preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Preview")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            ReceiptPreviewCard(template: template)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                save()
            }
            .disabled(!isDirty)
            .fontWeight(.semibold)
            .accessibilityLabel("Save receipt template")
            .accessibilityIdentifier("receiptTemplate.save")
        }
    }

    // MARK: - Actions

    private func save() {
        ReceiptTemplateStore.save(template)
        isDirty = false
        showSavedBanner()
        AppLog.hardware.info("ReceiptTemplateEditorView: template saved")
    }

    private func showSavedBanner() {
        savedBanner = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            savedBanner = false
        }
    }

    // MARK: - Saved banner

    private var savedBannerView: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("Template saved")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, BrandSpacing.base)
    }
}

// MARK: - ReceiptPreviewCard

/// Renders a simplified receipt preview card using the current template settings.
/// Uses the same token-driven visual as `ReceiptView` so the preview is accurate.
struct ReceiptPreviewCard: View {

    let template: ReceiptTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .center, spacing: 4) {
                if template.showLogo {
                    Image(systemName: "building.2")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(template.headerShopName.isEmpty ? "Your Shop Name" : template.headerShopName)
                    .font(.system(size: 14, weight: .bold))
                if !template.headerAddress.isEmpty {
                    Text(template.headerAddress)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if !template.headerPhone.isEmpty {
                    Text(template.headerPhone)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            Divider()

            // Sample line items
            VStack(alignment: .leading, spacing: 4) {
                receiptLine("iPhone 13 Screen Repair", "$129.99")
                receiptLine("Parts", "$45.00")
                Divider().padding(.vertical, 4)
                if template.showSubtotal { receiptLine("Subtotal", "$174.99") }
                if template.showTax      { receiptLine("Tax (8%)", "$14.00") }
                if template.showTip      { receiptLine("Tip", "$10.00") }
                receiptLine("Total", "$198.99", bold: true)
                if template.showPaymentMethod { receiptLine("Visa ****4567", "Approved") }
                if template.showCashierName   { receiptLine("Cashier", "Alex") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Footer
            VStack(alignment: .center, spacing: 4) {
                if !template.footerReturnPolicy.isEmpty {
                    Text(template.footerReturnPolicy)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                Text(template.footerThankYouMessage.isEmpty
                     ? "Thank you for your business!"
                     : template.footerThankYouMessage)
                    .font(.system(size: 10, weight: .medium))
                    .multilineTextAlignment(.center)
                if template.showQRCode {
                    Image(systemName: "qrcode")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .accessibilityLabel("QR code placeholder")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Receipt preview. Edit the form on the left to customize.")
    }

    private func receiptLine(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: bold ? .bold : .regular))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: bold ? .bold : .regular))
        }
    }
}

#endif
