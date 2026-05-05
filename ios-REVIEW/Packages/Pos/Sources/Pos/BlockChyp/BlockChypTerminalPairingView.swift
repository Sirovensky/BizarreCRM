#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.5 — Settings → Terminal: BlockChyp terminal pairing + heartbeat UI scaffold.
///
/// SCAFFOLD ONLY — no payment math is wired here. This screen lets a manager
/// enter the terminal IP / code and saves the pairing to Keychain under
/// `com.bizarrecrm.pos.terminal`. The actual charge flow lives in
/// `PosTerminalService` (Hardware package, Agent 2).
///
/// Keychain key: `com.bizarrecrm.pos.terminal`
/// Pairing model: `{ terminalCode: String, ipAddress: String, nickname: String? }`
///
/// Hard rule: NO BlockChyp SDK calls here. Rendering only.
@MainActor
public struct BlockChypTerminalPairingView: View {

    // MARK: - State

    @State private var terminalCode: String = ""
    @State private var ipAddress: String = ""
    @State private var nickname: String = ""
    @State private var isSaving: Bool = false
    @State private var savedSuccessfully: Bool = false
    @State private var errorMessage: String?

    /// Whether a pairing is already stored in Keychain (loaded on appear).
    @State private var hasPairing: Bool = false
    @State private var pairedNickname: String?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Keychain key (internal to this file)

    private static let keychainKey = "com.bizarrecrm.pos.terminal"

    // MARK: - Body

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                currentPairingSection
                pairNewSection
                helpSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Terminal Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await savePairing() }
                    }
                    .disabled(!canSave || isSaving)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("blockchyp.pair.save")
                }
            }
            .alert("Pairing saved", isPresented: $savedSuccessfully) {
                Button("OK") { dismiss() }
            } message: {
                Text("Terminal \(nickname.isEmpty ? ipAddress : nickname) is now paired.")
            }
        }
        .task { loadExistingPairing() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var currentPairingSection: some View {
        if hasPairing {
            Section {
                HStack(spacing: BrandSpacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(pairedNickname ?? "Paired terminal")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("Stored in Keychain")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        clearPairing()
                    } label: {
                        Text("Remove")
                            .font(.brandLabelLarge())
                    }
                    .accessibilityIdentifier("blockchyp.pair.remove")
                }
                .padding(.vertical, BrandSpacing.xs)
            } header: {
                Text("Current Pairing")
            }
        }
    }

    private var pairNewSection: some View {
        Section {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "number.square")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                TextField("Terminal code (from BlockChyp screen)", text: $terminalCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("blockchyp.pair.code")
            }

            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "network")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                TextField("IP address (e.g. 192.168.1.50)", text: $ipAddress)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("blockchyp.pair.ip")
            }

            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "tag")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("Nickname (optional, e.g. \"Front desk\")", text: $nickname)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("blockchyp.pair.nickname")
            }

            if let err = errorMessage {
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("blockchyp.pair.error")
            }
        } header: {
            Text(hasPairing ? "Replace Pairing" : "Pair Terminal")
        } footer: {
            Text("The terminal code appears on the BlockChyp reader screen. Pairing is stored locally in Keychain — never sent to a third-party server.")
                .font(.brandLabelSmall())
        }
    }

    private var helpSection: some View {
        Section {
            Label {
                Text("Heartbeat status is shown on the POS screen when a terminal is paired.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Label {
                Text("Card payments require a paired, reachable terminal. Manual-keyed cards require manager PIN.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } icon: {
                Image(systemName: "creditcard")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Logic

    private var canSave: Bool {
        !terminalCode.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ipAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func savePairing() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let code = terminalCode.trimmingCharacters(in: .whitespaces)
        let ip = ipAddress.trimmingCharacters(in: .whitespaces)
        let nick = nickname.trimmingCharacters(in: .whitespaces)

        // Validate IP format (basic heuristic — full validation deferred to SDK)
        guard ip.split(separator: ".").count == 4 || ip.contains(":") else {
            errorMessage = "Enter a valid IP address (e.g. 192.168.1.50)."
            return
        }

        // Encode pairing as JSON and persist to Keychain via `PairingKeychainStore`.
        let pairing = TerminalPairing(code: code, ipAddress: ip, nickname: nick.isEmpty ? nil : nick)
        guard let data = try? JSONEncoder().encode(pairing) else {
            errorMessage = "Encoding error — please try again."
            return
        }
        PairingKeychainStore.save(data: data, key: Self.keychainKey)

        AppLog.pos.info("BlockChyp terminal pairing saved: ip=\(ip) code=\(code)")
        BrandHaptics.success()
        savedSuccessfully = true
    }

    private func loadExistingPairing() {
        guard let data = PairingKeychainStore.load(key: Self.keychainKey),
              let pairing = try? JSONDecoder().decode(TerminalPairing.self, from: data) else {
            hasPairing = false
            return
        }
        hasPairing = true
        pairedNickname = pairing.nickname ?? pairing.ipAddress
        // Pre-fill so manager can see what's stored.
        terminalCode = pairing.code
        ipAddress = pairing.ipAddress
        nickname = pairing.nickname ?? ""
    }

    private func clearPairing() {
        PairingKeychainStore.delete(key: Self.keychainKey)
        hasPairing = false
        pairedNickname = nil
        terminalCode = ""
        ipAddress = ""
        nickname = ""
        AppLog.pos.info("BlockChyp terminal pairing removed")
    }
}

// MARK: - Pairing model

/// Lightweight Keychain-stored pairing record.
/// Raw PAN / auth data NEVER enters this struct — code + IP only.
public struct TerminalPairing: Codable, Sendable, Equatable {
    public let code: String
    public let ipAddress: String
    public let nickname: String?

    public init(code: String, ipAddress: String, nickname: String? = nil) {
        self.code = code
        self.ipAddress = ipAddress
        self.nickname = nickname
    }

    enum CodingKeys: String, CodingKey {
        case code
        case ipAddress = "ip_address"
        case nickname
    }
}

// MARK: - Minimal Keychain helper (scoped to this module)

/// Simple Keychain read/write/delete. Isolated to the Pos package so the
/// Hardware package (Agent 2) can wire the real SDK without touching this.
enum PairingKeychainStore {
    static func save(data: Data, key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Preview

#Preview("Pair terminal") {
    BlockChypTerminalPairingView()
        .preferredColorScheme(.dark)
}
#endif
