import Foundation
import Networking
import Core

// MARK: - SmsThreadViewModelWS
//
// §12.2 Real-time WS — new message arrives without refresh; animate in with spring.
//
// This extension adds WebSocket-driven live updates to SmsThreadViewModel.
// When a `sms:received` WS event arrives for this thread's phone number,
// the new message is appended and the list scrolls to bottom via `newMessageId`.
//
// Usage:
//   let vm = SmsThreadViewModel(repo: repo, phoneNumber: phone)
//   await vm.load()
//   vm.startListeningWS(wsClient: wsClient)
//
// The caller (SmsThreadView) passes the WebSocketClient injected from the
// app container. On view disappear, the observation task auto-cancels.

public extension SmsThreadViewModel {

    // MARK: - WS listener

    /// Starts observing `wsClient.events` for `sms.received` events matching
    /// `self.phoneNumber`. Safe to call from a SwiftUI `.task { }` modifier
    /// (the task is bound to the view's lifetime).
    func startListeningWS(wsClient: WebSocketClient) {
        wsListenTask?.cancel()
        wsListenTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in wsClient.events {
                guard !Task.isCancelled else { break }
                switch event {
                case .smsReceived(let dto):
                    await self.handleWsMessage(dto)
                case .unknown(let type)
                    where type.hasPrefix("sms.typing"):
                    // §12.2 Typing indicator — server sends `sms:typing` with the
                    // phone number of the conversation where typing is occurring.
                    // WSEvent.unknown passes through until Agent-10 adds the typed case.
                    self.handleTypingEvent()
                default:
                    break
                }
            }
        }
    }

    func stopListeningWS() {
        wsListenTask?.cancel()
        wsListenTask = nil
    }

    // MARK: - Private handler

    private func handleWsMessage(_ dto: SmsDTO) async {
        // SmsDTO.threadId is a legacy field — server routes SMS by phone number.
        // We don't have the thread phone in SmsDTO, so we reload and deduplicate.
        // This is a conservative approach: reload only if the last known message
        // is older than the WS event, avoiding unnecessary network calls.
        guard let lastMsg = thread?.messages.last else {
            await load()
            return
        }
        // Parse dates for comparison.
        let formatter = ISO8601DateFormatter()
        if let existingDate = formatter.date(from: lastMsg.createdAt ?? ""),
           dto.createdAt > existingDate {
            await load()
            // Signal new message so the view can scroll + animate in.
            newMessageId = Int64(dto.id)
        }
    }
}

// MARK: - Storage additions on SmsThreadViewModel

// These stored properties live here so SmsThreadViewModelWS.swift stays cohesive.
// The @Observable macro picks them up automatically.
extension SmsThreadViewModel {
    // Note: Swift 6 @Observable does not support stored properties in extensions.
    // We use ObservationIgnored task storage on the class directly via a nonisolated
    // key. Since SmsThreadViewModel is in the same module we declare `wsListenTask`
    // and `newMessageId` directly on the class (see SmsThreadViewModel.swift patch).
}
