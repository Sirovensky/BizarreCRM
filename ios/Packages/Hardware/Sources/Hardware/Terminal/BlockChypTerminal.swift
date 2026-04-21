import Foundation
import Core
import Persistence

// §17.3 BlockChyp terminal pairing — Phase 5
//
// HTTP-direct implementation of `CardTerminal`.
// Docs: https://docs.blockchyp.com/rest-api/
//
// Network peer exception: requests go to api.blockchyp.com, a second peer
// beyond APIClient.baseURL.  This is acceptable: BlockChyp is the tenant's
// payment processor; raw card data never leaves the terminal (PCI §28).
//
// Keychain keys:
//   "hardware.blockchyp_auth"  — JSON-encoded BlockChypCredentials
//   "hardware.blockchyp_terminal_name" — paired terminal name

// MARK: - BlockChypTerminal

/// HTTP-direct `CardTerminal` implementation for BlockChyp semi-integrated model.
///
/// Local mode and cloud-relay mode are transparent to this implementation —
/// the `/api/terminal/pair` and `/api/charge` endpoints handle routing.
public actor BlockChypTerminal: CardTerminal {

    // MARK: - Constants

    private static let baseURL = "https://api.blockchyp.com"
    private static let keychainAuthKey = KeychainKey.blockChypAuth
    private static let keychainTerminalNameKey = "hardware.blockchyp_terminal_name"

    // MARK: - Dependencies

    private let session: URLSession
    private let keychain: KeychainStore

    // MARK: - In-flight cancel support

    private var activePairingTask: Task<Void, Error>?
    private var activeChargeTask: Task<TerminalTransaction, Error>?

    // MARK: - Init

    public init(
        session: URLSession = .shared,
        keychain: KeychainStore = .shared
    ) {
        self.session = session
        self.keychain = keychain
    }

    // MARK: - CardTerminal: isPaired / pairedTerminalName

    public var isPaired: Bool {
        keychain.get(Self.keychainAuthKey) != nil
    }

    public var pairedTerminalName: String? {
        UserDefaults.standard.string(forKey: Self.keychainTerminalNameKey)
    }

    // MARK: - CardTerminal: pair

    public func pair(
        apiCredentials: BlockChypCredentials,
        activationCode: String,
        terminalName: String
    ) async throws {
        AppLog.hardware.info("BlockChypTerminal: pairing terminal '\(terminalName, privacy: .public)'")

        let requestBody = PairRequest(
            activationCode: activationCode,
            terminalName: terminalName
        )
        let _ = try await post(
            path: "/api/terminal/pair",
            body: requestBody,
            credentials: apiCredentials,
            responseType: PairResponse.self
        )

        // Persist credentials + name on success
        try saveCredentials(apiCredentials)
        UserDefaults.standard.set(terminalName, forKey: Self.keychainTerminalNameKey)
        AppLog.hardware.info("BlockChypTerminal: paired successfully as '\(terminalName, privacy: .public)'")
    }

    // MARK: - CardTerminal: charge

    public func charge(
        amountCents: Int,
        tipCents: Int,
        metadata: [String: String]
    ) async throws -> TerminalTransaction {
        let credentials = try loadCredentials()
        guard let name = UserDefaults.standard.string(forKey: Self.keychainTerminalNameKey) else {
            throw TerminalError.notPaired
        }

        AppLog.hardware.info("BlockChypTerminal: charging \(amountCents)¢ + tip \(tipCents)¢ on '\(name, privacy: .public)'")

        let amount = formatCents(amountCents)
        let tip = formatCents(tipCents)

        let requestBody = ChargeRequest(
            terminalName: name,
            amount: amount,
            tipAmount: tip,
            orderRef: metadata["orderRef"],
            description: metadata["description"]
        )
        let response = try await post(
            path: "/api/charge",
            body: requestBody,
            credentials: credentials,
            responseType: ChargeResponse.self
        )

        let txn = TerminalTransaction(
            id: response.transactionId ?? UUID().uuidString,
            approved: response.approved ?? false,
            approvalCode: response.authCode,
            amountCents: amountCents,
            tipCents: tipCents,
            cardBrand: response.cardBrand,
            cardLast4: response.maskedPan.map { String($0.suffix(4)) },
            receiptHtml: nil, // BlockChyp doesn't return HTML receipt directly
            capturedAt: Date(),
            errorMessage: response.responseDescription
        )
        AppLog.hardware.info("BlockChypTerminal: charge \(txn.approved ? "approved" : "declined") txnId=\(txn.id, privacy: .private)")
        return txn
    }

    // MARK: - CardTerminal: reverse

    public func reverse(
        transactionId: String,
        amountCents: Int
    ) async throws -> TerminalTransaction {
        let credentials = try loadCredentials()
        guard let name = UserDefaults.standard.string(forKey: Self.keychainTerminalNameKey) else {
            throw TerminalError.notPaired
        }

        AppLog.hardware.info("BlockChypTerminal: reversing txn \(transactionId, privacy: .private) \(amountCents)¢")

        let requestBody = ReverseRequest(
            terminalName: name,
            transactionId: transactionId,
            amount: formatCents(amountCents)
        )
        let response = try await post(
            path: "/api/reverse",
            body: requestBody,
            credentials: credentials,
            responseType: ChargeResponse.self
        )

        return TerminalTransaction(
            id: response.transactionId ?? UUID().uuidString,
            approved: response.approved ?? false,
            approvalCode: response.authCode,
            amountCents: amountCents,
            tipCents: 0,
            cardBrand: response.cardBrand,
            cardLast4: response.maskedPan.map { String($0.suffix(4)) },
            receiptHtml: nil,
            capturedAt: Date(),
            errorMessage: response.responseDescription
        )
    }

    // MARK: - CardTerminal: cancel

    public func cancel() async {
        AppLog.hardware.info("BlockChypTerminal: cancel requested")
        activeChargeTask?.cancel()
        activeChargeTask = nil
    }

    // MARK: - CardTerminal: ping

    public func ping() async throws -> TerminalPingResult {
        let credentials = try loadCredentials()
        guard let name = UserDefaults.standard.string(forKey: Self.keychainTerminalNameKey) else {
            throw TerminalError.notPaired
        }

        let start = Date()
        let requestBody = PingRequest(terminalName: name)
        let response = try await post(
            path: "/api/terminal-locate",
            body: requestBody,
            credentials: credentials,
            responseType: PingResponse.self
        )
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        let ok = response.success ?? false
        AppLog.hardware.info("BlockChypTerminal: ping ok=\(ok) latency=\(latency)ms")
        return TerminalPingResult(ok: ok, latencyMs: latency)
    }

    // MARK: - CardTerminal: unpair

    public func unpair() async {
        AppLog.hardware.info("BlockChypTerminal: unpairing")
        try? keychain.remove(Self.keychainAuthKey)
        UserDefaults.standard.removeObject(forKey: Self.keychainTerminalNameKey)
    }

    // MARK: - Private: Keychain helpers

    private func saveCredentials(_ credentials: BlockChypCredentials) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TerminalError.pairingFailed("Failed to encode credentials")
        }
        do {
            try keychain.set(json, for: Self.keychainAuthKey)
        } catch {
            throw TerminalError.pairingFailed("Keychain write failed: \(error.localizedDescription)")
        }
    }

    private func loadCredentials() throws -> BlockChypCredentials {
        guard let json = keychain.get(Self.keychainAuthKey),
              let data = json.data(using: .utf8) else {
            throw TerminalError.notPaired
        }
        do {
            return try JSONDecoder().decode(BlockChypCredentials.self, from: data)
        } catch {
            throw TerminalError.notPaired
        }
    }

    // MARK: - Private: HTTP helper

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        credentials: BlockChypCredentials,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        guard let url = URL(string: Self.baseURL + path) else {
            throw TerminalError.unreachable
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = try encoder.encode(body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Apply BlockChyp authentication headers
        let authHeaders = BlockChypSigner.authHeaders(credentials: credentials, body: bodyData)
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, httpResponse): (Data, URLResponse)
        do {
            (data, httpResponse) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw AppError.network(underlying: urlError)
        } catch {
            throw AppError.unknown(underlying: error)
        }

        if let http = httpResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8)
            throw AppError.fromHttp(statusCode: http.statusCode, message: message)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw AppError.decoding(type: String(describing: ResponseBody.self), underlying: error)
        }
    }

    // MARK: - Private: cent formatter

    private func formatCents(_ cents: Int) -> String {
        let dollars = cents / 100
        let remainder = abs(cents % 100)
        return String(format: "%d.%02d", dollars, remainder)
    }
}

// MARK: - Request / Response DTOs

// These DTOs are private to the actor; only `TerminalTransaction` and
// `TerminalPingResult` escape to callers.

private struct PairRequest: Encodable {
    let activationCode: String
    let terminalName: String
}

private struct PairResponse: Decodable {
    let success: Bool?
    let error: String?
    let responseDescription: String?
}

private struct ChargeRequest: Encodable {
    let terminalName: String
    let amount: String
    let tipAmount: String?
    let orderRef: String?
    let description: String?
}

private struct ReverseRequest: Encodable {
    let terminalName: String
    let transactionId: String
    let amount: String
}

private struct ChargeResponse: Decodable {
    let approved: Bool?
    let authCode: String?
    let transactionId: String?
    let maskedPan: String?
    let cardBrand: String?
    let responseDescription: String?
}

private struct PingRequest: Encodable {
    let terminalName: String
}

private struct PingResponse: Decodable {
    let success: Bool?
    let ipAddress: String?
    let cloudRelayEnabled: Bool?
}
