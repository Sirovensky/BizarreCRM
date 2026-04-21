import SwiftUI
import Core
import DesignSystem
import Networking
import Observation

// MARK: - ChangelogEntry

public struct ChangelogEntry: Identifiable, Decodable, Sendable {
    public let id: String
    public let version: String
    public let date: String
    public let highlights: [String]
    public let readMoreURL: String?

    enum CodingKeys: String, CodingKey {
        case id, version, date, highlights
        case readMoreURL = "readMoreUrl"
    }

    public init(id: String, version: String, date: String, highlights: [String], readMoreURL: String? = nil) {
        self.id = id
        self.version = version
        self.date = date
        self.highlights = highlights
        self.readMoreURL = readMoreURL
    }
}

// MARK: - WhatsNewViewModel

@MainActor
@Observable
final class WhatsNewViewModel {
    var entries: [ChangelogEntry] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let api: (any APIClient)?

    init(api: (any APIClient)? = APIClientHolder.current) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let api else {
            errorMessage = "No server connection."
            return
        }
        do {
            let version = Platform.appVersion
            let query = [URLQueryItem(name: "version", value: version)]
            let list = try await api.get("/app/changelog", query: query, as: [ChangelogEntry].self)
            entries = list
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - WhatsNewHelpView

/// Help → "Release notes". Reads `GET /app/changelog?version=X.Y.Z`.
public struct WhatsNewHelpView: View {

    @State private var vm = WhatsNewViewModel()
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView("Loading release notes…")
                        .accessibilityLabel("Loading changelog")
                } else if let err = vm.errorMessage {
                    errorView(message: err)
                } else if vm.entries.isEmpty {
                    emptyView
                } else {
                    entriesList
                }
            }
        }
        .navigationTitle("What's New")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await vm.load() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var entriesList: some View {
        List(vm.entries) { entry in
            Section {
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    ForEach(entry.highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: BrandSpacing.sm) {
                            Circle()
                                .fill(Color.bizarreOrange)
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                                .accessibilityHidden(true)
                            Text(highlight)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                        }
                    }
                    if let urlString = entry.readMoreURL, let url = URL(string: urlString) {
                        Button("Read more") { openURL(url) }
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityLabel("Read more about version \(entry.version)")
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
                .listRowBackground(Color.bizarreSurface1)
            } header: {
                HStack {
                    Text("Version \(entry.version)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                    Spacer()
                    Text(entry.date)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Version \(entry.version), \(entry.date)")
                .accessibilityAddTraits(.isHeader)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No release notes yet.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.vertical, BrandSpacing.sm)
                .brandGlass(.regular, in: Capsule(), interactive: true)
                .accessibilityLabel("Retry loading release notes")
        }
        .padding(BrandSpacing.base)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        WhatsNewHelpView()
    }
}
#endif
