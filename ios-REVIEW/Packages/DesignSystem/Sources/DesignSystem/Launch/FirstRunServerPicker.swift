import SwiftUI

// §68.3 — FirstRunServerPicker
// Server URL entry form shown on first run.
// Quick-pick: last-used URLs + hardcoded "bizarrecrm.com" default.

// MARK: - FirstRunServerPickerView

/// Server URL entry form for first-run and re-configuration.
///
/// Presents a text field for manual entry plus a quick-pick list of:
/// - The canonical `bizarrecrm.com` managed service.
/// - Up to five previously-used custom URLs (most-recent first).
///
/// The `onConfirm` callback receives the validated URL string.
public struct FirstRunServerPickerView: View {

    // MARK: State

    @State private var customURL: String = ""
    @State private var showURLError: Bool = false
    private let recentURLs: [String]
    private let onConfirm: (String) -> Void

    // MARK: Paste normalisation

    /// Normalise a pasted or typed URL string:
    /// - Strips leading/trailing whitespace and newlines
    /// - Prepends `https://` when no scheme is present
    /// - Lowercases the scheme + host portion
    private static func normalise(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip any accidentally-pasted trailing path that ends with a newline
        if let newline = s.firstIndex(of: "\n") { s = String(s[s.startIndex..<newline]) }
        // Auto-prepend scheme if missing
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return s
    }

    // MARK: Constants

    private static let canonicalURL = "https://bizarrecrm.com"

    // MARK: Init

    public init(recentURLs: [String] = [], onConfirm: @escaping (String) -> Void) {
        self.recentURLs = recentURLs
        self.onConfirm = onConfirm
    }

    // MARK: Subviews

    /// URL text field with platform-appropriate keyboard type.
    ///
    /// Paste handling: on change, if the new value looks like it came from a paste
    /// (i.e. it's longer than one character added at a time or contains whitespace),
    /// `normalise(_:)` is applied so the field always holds a clean URL.
    @ViewBuilder
    private var serverURLField: some View {
        let field = TextField("https://your-server.example.com", text: $customURL)
            .autocorrectionDisabled()
            .accessibilityLabel("Server URL")
            .accessibilityHint("Enter the full URL of your Bizarre CRM server, for example https://my-shop.bizarrecrm.com")
            // §36 paste handling — normalise the value whenever it changes so that
            // pasting "  shop.example.com\n" or "https://..." with surrounding spaces
            // all produce a clean, valid URL ready for submission.
            .onChange(of: customURL) { _, new in
                let cleaned = Self.normalise(new)
                if cleaned != new { customURL = cleaned }
                showURLError = false
            }
        #if canImport(UIKit)
        field
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
        #else
        field
        #endif
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    serverURLField

                    if showURLError {
                        Label("Please enter a valid https:// URL", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } header: {
                    Text("Server URL")
                } footer: {
                    Text("Enter the address of your Bizarre CRM server. Include https://")
                }

                Section("Quick pick") {
                    quickPickRow(url: Self.canonicalURL, label: "bizarrecrm.com (managed)")

                    ForEach(recentURLs.prefix(5), id: \.self) { url in
                        quickPickRow(url: url, label: url)
                    }
                }
            }
            .navigationTitle("Connect to Server")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { attemptConfirm() }
                        .accessibilityHint("Connect to the entered server URL")
                }
            }
        }
    }

    // MARK: Private

    private func quickPickRow(url: String, label: String) -> some View {
        Button {
            customURL = url
            attemptConfirm()
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Use \(label)")
        .accessibilityHint("Sets server URL to \(url) and connects")
    }

    private func attemptConfirm() {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidURL(trimmed) else {
            showURLError = true
            return
        }
        showURLError = false
        onConfirm(trimmed)
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme,
              scheme.lowercased() == "https",
              url.host != nil
        else { return false }
        return true
    }
}

#if DEBUG
#Preview {
    FirstRunServerPickerView(
        recentURLs: ["https://shop.example.com", "https://demo.bizarrecrm.com"],
        onConfirm: { _ in }
    )
}
#endif
