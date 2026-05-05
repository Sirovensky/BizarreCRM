import SwiftUI
import Core
#if canImport(UIKit)
import UIKit
import Contacts
#endif

// MARK: - §25.4 Share Sheet helpers

// MARK: - Share item builder

/// §25.4 — Builds share items for `ShareLink` / `UIActivityViewController`.
/// Centralises all share-sheet payloads in one place so format is consistent.
public enum ShareItem {

    // MARK: - Invoice / Estimate / Receipt PDF

    /// PDF share item generated from a pre-rendered `Data` blob.
    /// Caller uses `UIPrintPageRenderer` to produce the PDF; this wraps it
    /// for the system share sheet.
    public struct PDFPayload: Transferable {
        public let data: Data
        public let filename: String

        public init(data: Data, filename: String) {
            self.data = data
            self.filename = filename
        }

        public static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .pdf) { payload in
                payload.data
            }
        }
    }

    // MARK: - Customer vCard

    #if canImport(UIKit)
    /// §25.4 — Produces a vCard `Data` blob from a minimal customer record.
    public static func vCard(
        firstName: String,
        lastName: String,
        phone: String?,
        email: String?
    ) -> Data? {
        let contact = CNMutableContact()
        contact.givenName  = firstName
        contact.familyName = lastName
        if let phone {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                                   value: CNPhoneNumber(stringValue: phone))]
        }
        if let email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome,
                                                     value: email as NSString)]
        }
        return try? CNContactVCardSerialization.data(with: [contact])
    }
    #endif

    // MARK: - Ticket summary

    /// §25.4 — Formats a ticket summary as plain text + optional image.
    public static func ticketSummaryText(
        orderId: String,
        customerName: String?,
        device: String?,
        issue: String?,
        status: String
    ) -> String {
        var lines = ["Ticket #\(orderId)"]
        if let c = customerName { lines.append("Customer: \(c)") }
        if let d = device       { lines.append("Device: \(d)") }
        if let i = issue        { lines.append("Issue: \(i)") }
        lines.append("Status: \(status)")
        lines.append("— BizarreCRM")
        return lines.joined(separator: "\n")
    }

    // MARK: - Public tracking link

    /// §25.4 — Share URL for public ticket tracking page.
    /// Uses Universal Link for cloud tenants, custom scheme fallback for self-hosted.
    public static func trackingURL(shortId: String, tenantSlug: String?, isCloud: Bool) -> URL? {
        if isCloud {
            return URL(string: "https://app.bizarrecrm.com/public/tracking/\(shortId)")
        } else if let slug = tenantSlug {
            return URL(string: "bizarrecrm://\(slug)/track/\(shortId)")
        }
        return nil
    }
}

// MARK: - Share button view

/// §25.4 — A pre-styled share button that opens the system share sheet
/// for a given set of share items. Works on iPhone (bottom sheet) and
/// iPad (popover anchored to the button).
///
/// Usage:
/// ```swift
/// ShareButton(items: [invoicePDF, "Invoice #1234"], label: "Share Invoice")
/// ```
public struct ShareButton<Label: View>: View {
    let items: [Any]
    @ViewBuilder let label: () -> Label

    public init(items: [Any], @ViewBuilder label: @escaping () -> Label) {
        self.items = items
        self.label = label
    }

    public var body: some View {
        #if canImport(UIKit)
        ShareSheetButton(items: items, label: label)
        #else
        EmptyView()
        #endif
    }
}

public extension ShareButton where Label == SwiftUI.Label<Text, Image> {
    /// Convenience initialiser with system image.
    init(items: [Any], title: String, systemImage: String) {
        self.init(items: items) {
            SwiftUI.Label(title, systemImage: systemImage)
        }
    }
}

#if canImport(UIKit)
// MARK: - UIKit presenter (needed for iPad popover anchor)

private struct ShareSheetButton<Label: View>: View {
    let items: [Any]
    @ViewBuilder let label: () -> Label
    @State private var isPresenting: Bool = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            label()
        }
        .background(ShareSheetPresenter(isPresenting: $isPresenting, items: items))
        .accessibilityAddTraits(.isButton)
    }
}

/// Thin UIViewControllerRepresentable that presents `UIActivityViewController`
/// with a proper popover anchor on iPad.
private struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var isPresenting: Bool
    let items: [Any]

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresenting, uiViewController.presentedViewController == nil else { return }
        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad: anchor to the host view to avoid crash
        avc.popoverPresentationController?.sourceView = uiViewController.view
        avc.popoverPresentationController?.sourceRect = CGRect(
            x: uiViewController.view.bounds.midX,
            y: uiViewController.view.bounds.midY,
            width: 0,
            height: 0
        )
        avc.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { isPresenting = false }
        }
        uiViewController.present(avc, animated: true)
    }
}
#endif

// MARK: - Watermarked image helper

/// §25.4 — Draws a logo watermark on a `UIImage` before sharing.
/// Watermark is drawn bottom-right at 20% opacity.
#if canImport(UIKit)
public extension UIImage {
    /// Returns a copy of the receiver with a BizarreCRM text watermark.
    func watermarked(logoText: String = "BizarreCRM") -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            draw(at: .zero)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.04, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.2),
            ]
            let text = logoText as NSString
            let textSize = text.size(withAttributes: attrs)
            let margin: CGFloat = size.width * 0.02
            let origin = CGPoint(
                x: size.width  - textSize.width  - margin,
                y: size.height - textSize.height - margin
            )
            text.draw(at: origin, withAttributes: attrs)
        }
    }
}
#endif
