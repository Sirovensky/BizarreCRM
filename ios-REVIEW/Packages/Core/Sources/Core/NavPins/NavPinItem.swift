import Foundation
import UniformTypeIdentifiers

// §1.5 Pin-from-overflow drag — NavPinItem
//
// Represents a single pinnable navigation destination.
// Transferable conformance enables SwiftUI drag-and-drop between the
// More menu (source) and the primary sidebar / tab bar (drop target).

/// A lightweight, immutable value type representing a pinnable nav destination.
///
/// `Transferable` is provided via a JSON `CodableRepresentation` so the system
/// drag session can carry the item across SwiftUI view boundaries.
public struct NavPinItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String

    public init(id: String, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

// MARK: - Transferable

import SwiftUI

@available(iOS 16.0, *)
extension NavPinItem: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .navPinItem)
    }
}

// MARK: - UTType

extension UTType {
    /// Custom uniform type identifier for NavPinItem drag payloads.
    public static let navPinItem = UTType(exportedAs: "com.bizarrecrm.navpinitem")
}
