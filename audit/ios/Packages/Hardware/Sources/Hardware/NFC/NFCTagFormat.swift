import Foundation

// MARK: - NFC tag format selector
//
// §17.5 — "NDEF vs raw" — NDEF is the primary supported format; raw MIFARE /
// NTAG / FeliCa is a fallback for tenants who already have legacy inventory
// tags written outside our app. Each tenant picks one default in
// Settings → Hardware → NFC.
//
// Server schema and write-path are blocked behind NFC-PARITY-001 (see §17.5
// preamble); this enum + store ship now so the local wiring is ready and the
// settings surface can be assembled the moment parity lands.

/// Formats the iOS NFC reader can decode.
public enum NFCTagFormat: String, Sendable, CaseIterable, Codable, Identifiable {
    /// `NFCNDEFReaderSession` — simplest, broadest tag support, lowest entitlement
    /// surface. URL / text records map cleanly onto our `nfc_tag_id` column.
    case ndef

    /// `NFCTagReaderSession` over MIFARE Classic / Ultralight / NTAG21x. Used by
    /// some inventory sticker vendors. Requires explicit AID list in Info.plist
    /// (`com.apple.developer.nfc.readersession.iso7816.select-identifiers`).
    case mifare

    /// FeliCa for Japanese transit / loyalty tags. Rare in our base; opt-in.
    case felica

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ndef:    return "NDEF (recommended)"
        case .mifare:  return "MIFARE / NTAG (raw)"
        case .felica:  return "FeliCa"
        }
    }

    public var displayDescription: String {
        switch self {
        case .ndef:
            return "Standard format. Works with the tags we ship and most third-party stickers."
        case .mifare:
            return "Raw MIFARE / NTAG access. Use only if you already have non-NDEF inventory tags."
        case .felica:
            return "Japanese transit / loyalty tags. Most tenants outside Japan should leave this off."
        }
    }

    public var requiresEntitlementUpdate: Bool {
        // NDEF works on the default reader entitlement; the others need the
        // ISO-7816 / FeliCa formats added in `com.apple.developer.nfc.readersession.formats`.
        self != .ndef
    }
}

// MARK: - Persistence

/// UserDefaults-backed store for the per-tenant default tag format.
/// Migration path to GRDB once the server schema (NFC-PARITY-001) lands.
public final class NFCTagFormatStore: @unchecked Sendable {

    public static let shared = NFCTagFormatStore()

    private let defaultsKey = "com.bizarrecrm.hardware.nfc.tagFormat"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var preferredFormat: NFCTagFormat {
        get {
            guard let raw = defaults.string(forKey: defaultsKey),
                  let format = NFCTagFormat(rawValue: raw)
            else { return .ndef }
            return format
        }
        set {
            defaults.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    public func reset() {
        defaults.removeObject(forKey: defaultsKey)
    }
}
