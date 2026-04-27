import SwiftUI

// MARK: - §30.13 #if DEBUG component catalog
//
// Every reusable brand component rendered with all variants for visual regression.
// Access from Settings → Diagnostics → Component Catalog (debug builds only).
//
// Three toast/banner/snackbar types also demonstrated per §30.13.

#if DEBUG

// MARK: - ComponentCatalogView

public struct ComponentCatalogView: View {

    @State private var showToastSuccess = false
    @State private var showToastWarning = false
    @State private var showToastDanger  = false
    @State private var selectedChipStatus: String = "open"
    @State private var textFieldValue = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                buttonSection
                cardSection
                chipSection
                badgeSection
                textFieldSection
                toastSection
                bannerSection
                loadingSection
                illustrationSection
                motionSection
                typographySection
                colorSection
            }
            .navigationTitle("Component Catalog")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sections

    private var buttonSection: some View {
        Section("BrandButton") {
            NavigationLink("Button variants") {
                buttonVariantsView
            }
        }
    }

    private var cardSection: some View {
        Section("BrandCard") {
            NavigationLink("Card variants") {
                cardVariantsView
            }
        }
    }

    private var chipSection: some View {
        Section("BrandChip / StatusPill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["open", "in_progress", "waiting", "closed", "cancelled"], id: \.self) { status in
                        StatusPill(status: status)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var badgeSection: some View {
        Section("Badges") {
            HStack(spacing: 12) {
                SemanticBadge(label: "3", style: .danger)
                SemanticBadge(label: "12", style: .warning)
                SemanticBadge(label: "✓", style: .success)
                SemanticBadge(label: "i", style: .info)
            }
        }
    }

    private var textFieldSection: some View {
        Section("BrandTextField") {
            BrandTextField(
                label: "Customer name",
                placeholder: "John Smith",
                text: $textFieldValue
            )
        }
    }

    private var toastSection: some View {
        Section("Toast / Snackbar") {
            Button("Show success toast") { showToastSuccess = true }
            Button("Show warning toast") { showToastWarning = true }
            Button("Show danger toast")  { showToastDanger  = true }
        }
    }

    private var bannerSection: some View {
        Section("BrandBanner") {
            NavigationLink("Banner variants") {
                bannerVariantsView
            }
        }
    }

    private var loadingSection: some View {
        Section("Loading / Skeleton") {
            NavigationLink("Skeleton rows") {
                SkeletonList(rowCount: 5)
                    .navigationTitle("Skeleton")
            }
        }
    }

    private var illustrationSection: some View {
        Section("Illustrations") {
            NavigationLink("All illustrations") {
                ScrollView {
                    LazyVGrid(columns: [.init(), .init(), .init()], spacing: 20) {
                        ForEach(IllustrationType.allCases, id: \.rawValue) { type in
                            VStack(spacing: 6) {
                                BrandIllustration(type)
                                    .foregroundStyle(.orange)
                                    .frame(width: 48, height: 48)
                                Text(type.rawValue.split(separator: ".").last.map(String.init) ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Illustrations")
            }
        }
    }

    private var motionSection: some View {
        Section("Motion tokens") {
            NavigationLink("Animation catalog") {
                MotionCatalogPreview()
            }
        }
    }

    private var typographySection: some View {
        Section("Typography") {
            NavigationLink("Type scale") {
                typeScaleView
            }
        }
    }

    private var colorSection: some View {
        Section("Color tokens") {
            NavigationLink("Color palette") {
                colorPaletteView
            }
        }
    }

    // MARK: - Sub-views

    private var buttonVariantsView: some View {
        List {
            Section("Sizes × Styles") {
                ForEach(["Primary", "Secondary", "Ghost", "Destructive"], id: \.self) { style in
                    BrandButton(style == "Primary" ? .primary : style == "Secondary" ? .secondary : style == "Ghost" ? .ghost : .destructive,
                                size: .md,
                                label: "\(style) md") { }
                }
            }
        }
        .navigationTitle("Buttons")
    }

    private var cardVariantsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                BrandCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Standard Card").font(.headline)
                        Text("Elevated surface with stroke + shadow.").font(.caption)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Cards")
    }

    private var bannerVariantsView: some View {
        VStack(spacing: 12) {
            BrandBanner(kind: .info,    message: "Syncing...",            action: nil)
            BrandBanner(kind: .warning, message: "Offline",               action: nil)
            BrandBanner(kind: .danger,  message: "Sync failed. Retry.",   action: ("Retry", {}))
            BrandBanner(kind: .success, message: "All changes synced.",   action: nil)
        }
        .padding()
        .navigationTitle("Banners")
    }

    private var typeScaleView: some View {
        List {
            ForEach([
                ("largeTitle", Font.largeTitle),
                ("title",       Font.title),
                ("title2",      Font.title2),
                ("title3",      Font.title3),
                ("headline",    Font.headline),
                ("body",        Font.body),
                ("callout",     Font.callout),
                ("subheadline", Font.subheadline),
                ("footnote",    Font.footnote),
                ("caption",     Font.caption),
                ("caption2",    Font.caption2),
            ], id: \.0) { name, font in
                Text("Aa — \(name)")
                    .font(font)
            }
        }
        .navigationTitle("Typography")
    }

    private var colorPaletteView: some View {
        List {
            Section("Brand") {
                colorRow("brandPrimary", Color.orange)
                colorRow("brandSecondary", Color.teal)
                colorRow("brandTertiary", Color.pink)
            }
            Section("Status") {
                colorRow("success", Color.green)
                colorRow("warning", Color.yellow)
                colorRow("danger",  Color.red)
                colorRow("info",    Color.blue)
            }
        }
        .navigationTitle("Colors")
    }

    private func colorRow(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 32, height: 32)
            Text(name).font(.body)
        }
    }
}

// MARK: - MotionCatalogPreview

private struct MotionCatalogPreview: View {
    @State private var pulsing = false
    @State private var bouncing = false

    var body: some View {
        List {
            Section("Pulse") {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 40, height: 40)
                    .scaleEffect(pulsing ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }
            }
            Section("Spring bounce") {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.teal)
                    .frame(height: 44)
                    .offset(y: bouncing ? -8 : 0)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.5), value: bouncing)
                    .onTapGesture { bouncing.toggle() }
            }
        }
        .navigationTitle("Motion")
    }
}

// MARK: - Preview

#Preview("Component Catalog") {
    ComponentCatalogView()
}

#endif
