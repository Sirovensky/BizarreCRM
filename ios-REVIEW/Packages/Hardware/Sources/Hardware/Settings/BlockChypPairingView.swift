#if canImport(SwiftUI)
import SwiftUI
import Core

// §17.3 BlockChyp terminal pairing view — Phase 5
// Liquid Glass applied to navigation chrome + sheet header only.
// A11y labels on every interactive element.
// iPhone / iPad adaptive layout via Platform.isCompact.

// MARK: - BlockChypPairingView

/// Admin view for pairing a BlockChyp card terminal.
///
/// Step 1 (idle):     Enter activation code + terminal name → "Pair" button.
/// Step 2 (pairing):  Spinner + "Contacting terminal…" message.
/// Step 3 (paired):   Terminal name + last-used timestamp + "Test $1.00" + "Unpair".
/// Failure:           Error banner with retry option.
///
/// Wiring snippet (add to HardwareSettingsView or Settings navigation):
/// ```swift
/// NavigationLink("BlockChyp Terminal") {
///     BlockChypPairingView(viewModel: BlockChypPairingViewModel(terminal: BlockChypTerminal()))
/// }
/// ```
public struct BlockChypPairingView: View {

    // MARK: - Dependencies

    @State var viewModel: BlockChypPairingViewModel

    /// Credentials are provided by the parent (read from secure Settings store).
    /// In production, Settings/Payment injects real creds here.
    public var credentials: BlockChypCredentials

    // MARK: - Init

    public init(viewModel: BlockChypPairingViewModel, credentials: BlockChypCredentials) {
        self._viewModel = State(initialValue: viewModel)
        self.credentials = credentials
    }

    // MARK: - Body

    public var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .pairing:
                pairingView
            case .paired(let info):
                pairedView(info: info)
            case .testing:
                testingView
            case .failed(let message):
                failedView(message: message)
            }
        }
        .navigationTitle("Card Terminal")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .task { await viewModel.onAppear() }
        .confirmationDialog(
            "Unpair Terminal?",
            isPresented: $viewModel.showUnpairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unpair", role: .destructive) {
                Task { await viewModel.unpair() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the terminal pairing. You will need to re-enter an activation code to reconnect.")
        }
    }

    // MARK: - Step 1: Idle (enter activation code)

    private var idleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                instructionHeader
                activationCodeField
                terminalNameField
                pairButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .accessibilityLabel("Terminal Pairing Setup")
    }

    private var instructionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect BlockChyp Terminal", systemImage: "creditcard.viewfinder")
                .font(.headline)
                .accessibilityLabel("Connect BlockChyp Terminal")

            Text("On the terminal, go to Settings → Pair Device. An activation code will appear on the screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var activationCodeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activation Code")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Enter code from terminal screen", text: $viewModel.activationCode)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.default)
                .textInputAutocapitalization(.characters)
                #endif
                .accessibilityLabel("Activation code")
                .accessibilityHint("Enter the pairing code shown on the BlockChyp terminal screen")
        }
    }

    private var terminalNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Terminal Name")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("e.g. Counter 1", text: $viewModel.terminalName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("Terminal name")
                .accessibilityHint("A label to identify this terminal in the app")
        }
    }

    private var pairButton: some View {
        Button {
            Task { await viewModel.beginPairing(credentials: credentials) }
        } label: {
            Label("Pair Terminal", systemImage: "link")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.activationCode.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Pair terminal")
        .accessibilityHint("Starts the pairing process with the BlockChyp terminal")
    }

    // MARK: - Step 2: Pairing spinner

    private var pairingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .accessibilityLabel("Pairing in progress")
            Text("Contacting terminal…")
                .font(.headline)
            Text("Keep the terminal awake and on the pairing screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 3: Paired

    private func pairedView(info: TerminalInfo) -> some View {
        List {
            // Terminal status section
            Section {
                HStack {
                    Label(info.name, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Paired terminal: \(info.name)")
                    Spacer()
                    Text("Paired")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let lastUsed = info.lastUsedAt {
                    HStack {
                        Text("Last used")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastUsed, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                }
            } header: {
                Text("Terminal Status")
            }

            // Actions section
            Section {
                Button {
                    Task { await viewModel.testCharge() }
                } label: {
                    Label("Test Charge $1.00", systemImage: "dollarsign.circle")
                }
                .accessibilityLabel("Send test charge of one dollar")
                .accessibilityHint("Sends a $1.00 test transaction to verify the terminal is working")

                Button(role: .destructive) {
                    viewModel.confirmUnpair()
                } label: {
                    Label("Unpair Terminal", systemImage: "link.badge.minus")
                }
                .accessibilityLabel("Unpair this terminal")
                .accessibilityHint("Removes the pairing and clears stored credentials")
            } header: {
                Text("Actions")
            }
        }
        #if !os(macOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Testing spinner

    private var testingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .accessibilityLabel("Test charge in progress")
            Text("Sending test charge…")
                .font(.headline)
            Text("The terminal will prompt you to tap or insert a card. Use a test card.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Failure banner

    private func failedView(message: String) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error")

                Text("Pairing Failed")
                    .font(.title2.bold())

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityLabel(message)

                Button("Try Again") {
                    viewModel.retryFromFailure()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Retry pairing")
            }
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

#endif
