#if DEBUG
import Foundation

// §31 Test Fixtures Helpers — FixtureLoader
// Loads JSON fixtures from a test bundle, producing clear diagnostic errors
// when a fixture is missing or malformed.

/// Loads JSON fixture files from a `Bundle` and decodes them into typed values.
///
/// Usage (in a test target):
/// ```swift
/// let customer: Customer = try FixtureLoader(bundle: .module).load("customer_default")
/// let raw: [String: Any] = try FixtureLoader(bundle: .module).loadRaw("envelope_ok")
/// ```
public struct FixtureLoader: Sendable {

    // MARK: — Errors

    public enum LoaderError: Error, CustomStringConvertible {
        /// The named JSON file could not be found in the bundle.
        case fileNotFound(name: String, bundle: String)
        /// The file was found but could not be decoded into the expected type.
        case decodingFailed(name: String, type: String, underlying: Error)
        /// The file was found but its data could not be converted to a dictionary.
        case notAnObject(name: String)

        public var description: String {
            switch self {
            case let .fileNotFound(name, bundle):
                return "FixtureLoader: '\(name).json' not found in bundle '\(bundle)'. "
                    + "Make sure the file is added to the test target's Copy Bundle Resources phase."
            case let .decodingFailed(name, type, underlying):
                return "FixtureLoader: failed to decode '\(name).json' as \(type). Underlying: \(underlying)"
            case let .notAnObject(name):
                return "FixtureLoader: '\(name).json' is not a JSON object (top-level must be {…})."
            }
        }
    }

    // MARK: — Properties

    private let bundle: Bundle
    private let decoder: JSONDecoder

    // MARK: — Init

    /// - Parameters:
    ///   - bundle: The bundle that contains the `.json` fixture files.
    ///             In a Swift Package test target, pass `Bundle.module`.
    ///   - decoder: Optional custom decoder (defaults to one with `.iso8601` date strategy).
    public init(bundle: Bundle, decoder: JSONDecoder? = nil) {
        self.bundle = bundle
        if let decoder {
            self.decoder = decoder
        } else {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            self.decoder = d
        }
    }

    // MARK: — Public API

    /// Loads and decodes a JSON fixture file into `T`.
    ///
    /// - Parameter name: File name without the `.json` extension.
    /// - Throws: `LoaderError.fileNotFound` or `LoaderError.decodingFailed`.
    public func load<T: Decodable>(_ name: String) throws -> T {
        let data = try rawData(for: name)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LoaderError.decodingFailed(
                name: name,
                type: String(describing: T.self),
                underlying: error
            )
        }
    }

    /// Loads a JSON fixture and returns it as a raw `[String: Any]` dictionary.
    ///
    /// Useful when you want to inspect or mutate the payload before stubbing an HTTP response.
    ///
    /// - Parameter name: File name without the `.json` extension.
    /// - Throws: `LoaderError.fileNotFound` or `LoaderError.notAnObject`.
    public func loadRaw(_ name: String) throws -> [String: Any] {
        let data = try rawData(for: name)
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw LoaderError.notAnObject(name: name)
        }
        return obj
    }

    /// Loads a JSON fixture and returns the raw `Data`.
    ///
    /// - Parameter name: File name without the `.json` extension.
    /// - Throws: `LoaderError.fileNotFound`.
    public func loadData(_ name: String) throws -> Data {
        try rawData(for: name)
    }

    // MARK: — Private

    private func rawData(for name: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoaderError.fileNotFound(
                name: name,
                bundle: bundle.bundleIdentifier ?? bundle.bundlePath
            )
        }
        return try Data(contentsOf: url)
    }
}
#endif
