import Foundation

// §19 — Maps the raw `hw.machine` sysctlbyname identifier returned on
// physical iOS devices to a human-readable marketing name shown in
// About → Device. Keys are the strings returned by `sysctlbyname("hw.machine")`.

public enum DeviceModelMap {

    /// Returns the marketing name for a given hardware identifier, or `nil`
    /// when the identifier is unknown / not in the table.
    public static func name(for identifier: String) -> String? {
        return table[identifier]
    }

    // MARK: - Lookup table

    private static let table: [String: String] = [
        // iPhone 16 family
        "iPhone17,1": "iPhone 16",
        "iPhone17,2": "iPhone 16 Plus",
        "iPhone17,3": "iPhone 16 Pro",
        "iPhone17,4": "iPhone 16 Pro Max",
        // iPhone 15 family
        "iPhone16,1": "iPhone 15",
        "iPhone16,2": "iPhone 15 Plus",
        "iPhone16,3": "iPhone 15 Pro",
        "iPhone16,4": "iPhone 15 Pro Max",
        // iPhone 14 family
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        // iPhone 13 family
        "iPhone14,5": "iPhone 13",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        // iPhone 12 family
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        // Simulator
        "x86_64": "Simulator",
        "arm64": "Simulator",
    ]
}
