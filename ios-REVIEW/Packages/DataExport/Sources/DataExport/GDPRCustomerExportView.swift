import SwiftUI
import DesignSystem
import Core

// MARK: - GDPRCustomerExportView

/// Customer detail menu → "Download all data for this customer" (GDPR/CCPA).
/// iPhone: presented as a sheet. iPad: shown in detail panel.
public struct GDPRCustomerExportView: View {

    public let customerId: String
    public let customerName: String

    @State private var viewModel: DataExportViewModel
    @State private var progressViewModel: ExportProgressViewModel?
    @State private var showProgress: Bool = false

    @Environment(\.dismiss) private var dismiss

    public init(
        customerId: String,
        customerName: String,
        viewModel: DataExportViewModel
    ) {
        self.customerId = customerId
        self.customerName = customerName
        self._viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .onChange(of: viewModel.startedJob?.id) { _, newId in
            guard let job = viewModel.startedJob, newId != nil else { return }
            progressViewModel = ExportProgressViewModel(job: job, repository: viewModel.repository)
            showProgress = true
        }
        .sheet(isPresented: $showProgress) {
            if let pvm = progressViewModel {
                ExportProgressView(viewModel: pvm)
            }
        }
        .alert("Export Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            content
                .navigationTitle("Customer Data Export")
                .exportInlineTitleMode()
                .exportToolbarBackground()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .accessibilityLabel("Close")
                    }
                }
        }
        .presentationDetents([.medium])
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        content
            .navigationTitle("Customer Data Export")
            .exportToolbarBackground()
    }

    // MARK: - Shared content

    private var content: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Export data for")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(customerName)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What's included")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ForEach(gdprItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Button {
                Task { await viewModel.startCustomerExport(customerId: customerId) }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Requesting export…")
                } else {
                    Label("Download all data for this customer", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.brandGlassProminent)
            .tint(Color.accentColor)
            .disabled(viewModel.isLoading)
            .padding(.horizontal)
            .accessibilityLabel("Download all data for \(customerName)")
            .accessibilityHint("Requests a GDPR data package for this customer")

            Text("Per GDPR Article 20 and CCPA §1798.100, customers have the right to a portable copy of their data.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 24)
    }

    private let gdprItems: [String] = [
        "Profile & contact information",
        "Service history & tickets",
        "Invoices & payment records",
        "Device notes & photos",
        "SMS & communications",
        "Loyalty points & memberships"
    ]
}
