import SwiftUI
import Core
import DesignSystem

// MARK: - ReferenceLetterView
//
// §14 Reference letter: auto-generate PDF summarizing tenure + stats;
// manager customizes body before export.
//
// Entry point: EmployeeDetailView (admin) → "Generate Reference Letter" button.

public struct ReferenceLetterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ReferenceLetterViewModel

    public init(employee: ReferenceLetterEmployee, stats: ReferenceLetterStats) {
        _vm = State(wrappedValue: ReferenceLetterViewModel(employee: employee, stats: stats))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        headerCard
                        authorField
                        bodyEditor
                        if let err = vm.exportError {
                            Text(err)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreError)
                                .padding(.horizontal, BrandSpacing.base)
                        }
                        exportButton
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.lg)
                    .padding(.bottom, BrandSpacing.xl)
                }
            }
            .navigationTitle("Reference Letter")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $vm.showShareSheet) {
                if let data = vm.exportedData {
                    ShareSheetWrapper(data: data, filename: vm.filename)
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Reference Letter", systemImage: "doc.text")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Auto-generated from \(vm.employee.fullName)'s tenure and performance data. Edit the body below before exporting.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var authorField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Signed by")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("Your name (manager / owner)", text: $vm.authorName)
                .textFieldStyle(.plain)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .frame(minHeight: 44)
                .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                .accessibilityIdentifier("ref.letter.author")
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text("Letter body")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Button("Reset to default") { vm.resetBody() }
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
            }
            TextEditor(text: $vm.customBody)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(minHeight: 200)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                .accessibilityIdentifier("ref.letter.body")
                .accessibilityLabel("Letter body text")
        }
    }

    private var exportButton: some View {
        Button {
            Task { await vm.generateAndExport() }
        } label: {
            HStack {
                if vm.isGenerating {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(vm.isGenerating ? "Generating…" : "Export PDF")
                    .font(.brandBodyMedium().weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.plain)
        .background(.bizarreOrange, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.black)
        .disabled(vm.isGenerating || vm.authorName.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityIdentifier("ref.letter.export")
        .accessibilityLabel(vm.isGenerating ? "Generating PDF" : "Export reference letter as PDF")
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class ReferenceLetterViewModel {
    public let employee: ReferenceLetterEmployee
    public let stats: ReferenceLetterStats
    public var authorName: String = ""
    public var customBody: String = ""
    public private(set) var isGenerating: Bool = false
    public private(set) var exportError: String?
    public var showShareSheet: Bool = false
    public private(set) var exportedData: Data?
    public private(set) var filename: String = "reference_letter.pdf"

    public init(employee: ReferenceLetterEmployee, stats: ReferenceLetterStats) {
        self.employee = employee
        self.stats = stats
        // Pre-populate body with the auto-generated default so the manager can
        // edit it inline rather than starting from scratch.
        self.customBody = defaultBody
    }

    public func resetBody() {
        customBody = defaultBody
    }

    public func generateAndExport() async {
        guard !isGenerating else { return }
        isGenerating = true
        exportError = nil
        defer { isGenerating = false }
        do {
            let data = try ReferenceLetterExportService.generatePDF(
                employee: employee,
                stats: stats,
                authorName: authorName.trimmingCharacters(in: .whitespaces),
                customBody: customBody.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            exportedData = data
            filename = "Reference_Letter_\(employee.fullName.replacingOccurrences(of: " ", with: "_")).pdf"
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Default body

    private var defaultBody: String {
        let tenureStr: String
        if let start = stats.startDate {
            let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .none
            let end = stats.endDate.map { fmt.string(from: $0) } ?? "present"
            tenureStr = "from \(fmt.string(from: start)) to \(end)"
        } else {
            tenureStr = "as a valued team member"
        }

        return """
To whom it may concern,

It is my pleasure to recommend \(employee.fullName) for their next opportunity.

\(employee.firstName) joined our team as \(employee.role) and served with us \(tenureStr). During their tenure, they demonstrated strong professionalism, consistent performance, and a genuine commitment to customer satisfaction.

\(employee.firstName) was a valued member of our operations and I am confident they will bring the same dedication to their next role.

Please feel free to reach out with any questions.


Sincerely,
"""
    }
}

// MARK: - ShareSheetWrapper

#if canImport(UIKit)
import UIKit

private struct ShareSheetWrapper: UIViewControllerRepresentable {
    let data: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        let vc = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
