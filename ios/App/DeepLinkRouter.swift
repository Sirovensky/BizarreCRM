import Foundation
import Observation

@MainActor
@Observable
public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()

    public enum Destination: Hashable {
        case ticket(id: Int64)
        case createTicket
        case customer(id: Int64)
        case sms(phone: String)
        case posNew
        case posQuickSale
    }

    public private(set) var pending: Destination?

    private init() {}

    public func handle(_ url: URL) {
        guard url.scheme == "bizarrecrm" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let host = url.host else { return }

        switch host {
        case "ticket":
            if parts.first == "new" {
                pending = .createTicket
            } else if let idStr = parts.first, let id = Int64(idStr) {
                pending = .ticket(id: id)
            }
        case "customer":
            if let idStr = parts.first, let id = Int64(idStr) {
                pending = .customer(id: id)
            }
        case "sms":
            if let phone = parts.first {
                pending = .sms(phone: phone)
            }
        case "pos":
            switch parts.first {
            case "new-repair": pending = .posNew
            case "quick-sale": pending = .posQuickSale
            default: break
            }
        default:
            break
        }
    }

    public func consume() -> Destination? {
        defer { pending = nil }
        return pending
    }
}
