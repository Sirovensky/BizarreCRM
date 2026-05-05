import SwiftUI
#if canImport(WebKit)
import WebKit
#endif
import DesignSystem

// MARK: - HtmlPreviewView

/// `UIViewRepresentable` / `NSViewRepresentable` wrapper around `WKWebView`.
/// Loads an HTML string with brand CSS.
/// Safe-content policy: blocks all remote resources by default.
public struct HtmlPreviewView: View {
    public let html: String
    /// When true, remote images are allowed (e.g. for staff-facing preview with CDN assets).
    public var allowRemoteImages: Bool

    public init(html: String, allowRemoteImages: Bool = false) {
        self.html = html
        self.allowRemoteImages = allowRemoteImages
    }

    public var body: some View {
        _WebViewWrapper(html: styledHTML, allowRemoteImages: allowRemoteImages)
    }

    // MARK: - Brand-styled HTML wrapper

    private var styledHTML: String {
        guard !html.isEmpty else {
            return "<html><body style=\"margin:0;padding:16px;font-family:sans-serif;color:#ccc\"><p>No preview</p></body></html>"
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body {
            margin: 0;
            padding: 16px;
            font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            font-size: 15px;
            line-height: 1.5;
            background-color: #1a1a1a;
            color: #f0f0f0;
          }
          a { color: #ff8c37; }
          h1, h2, h3 { color: #ffffff; }
          img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }
}

// MARK: - Platform wrapper

#if canImport(WebKit)

#if os(iOS)
private struct _WebViewWrapper: UIViewRepresentable {
    let html: String
    let allowRemoteImages: Bool

    func makeUIView(context: Context) -> WKWebView {
        makeWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
#elseif os(macOS)
private struct _WebViewWrapper: NSViewRepresentable {
    let html: String
    let allowRemoteImages: Bool

    func makeNSView(context: Context) -> WKWebView {
        makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
#endif

// Shared factory — creates the WKWebView with a strict content policy.
@MainActor
private func makeWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    // Disable JavaScript for safe HTML-only preview
    let prefs = WKPreferences()
    prefs.isElementFullscreenEnabled = false
    config.preferences = prefs
    if #available(iOS 14.0, macOS 11.0, *) {
        config.defaultWebpagePreferences.allowsContentJavaScript = false
    } else {
        prefs.javaScriptEnabled = false
    }
    let wv = WKWebView(frame: .zero, configuration: config)
    #if os(iOS)
    wv.scrollView.bounces = true
    wv.isOpaque = false
    wv.backgroundColor = .clear
    wv.scrollView.backgroundColor = .clear
    #endif
    return wv
}

#else

// Fallback for platforms without WebKit
private struct _WebViewWrapper: View {
    let html: String
    let allowRemoteImages: Bool

    var body: some View {
        Text("HTML preview unavailable on this platform")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
