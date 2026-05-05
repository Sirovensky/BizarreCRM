import Foundation
import Networking

public extension APIClient {
    /// POST `/api/v1/timeclock/swap-requests`
    func createSwapRequest(body: SwapRequestBody) async throws -> ShiftSwapRequest {
        try await post("/api/v1/timeclock/swap-requests", body: body, as: ShiftSwapRequest.self)
    }

    /// GET `/api/v1/timeclock/swap-requests` — requests visible to the caller
    func getSwapRequests() async throws -> [ShiftSwapRequest] {
        try await get("/api/v1/timeclock/swap-requests", as: [ShiftSwapRequest].self)
    }

    /// POST `/api/v1/timeclock/swap-requests/:id/offer`
    func offerSwap(requestId: Int64, body: SwapOfferBody) async throws -> ShiftSwapRequest {
        try await post("/api/v1/timeclock/swap-requests/\(requestId)/offer", body: body, as: ShiftSwapRequest.self)
    }

    /// POST `/api/v1/timeclock/swap-requests/:id/approve`
    func approveSwap(requestId: Int64, approved: Bool) async throws -> ShiftSwapRequest {
        let body = SwapApproveBody(approved: approved)
        return try await post("/api/v1/timeclock/swap-requests/\(requestId)/approve", body: body, as: ShiftSwapRequest.self)
    }
}
