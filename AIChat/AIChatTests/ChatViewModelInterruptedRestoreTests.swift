@testable import AIChat
import Foundation
import Testing

/// 복원 시 ViewModel 통합: 자동 재전송 없음, canRetry, 디스크 write-back.
/// 순수 정규화 알고리즘은 `ChatHistoryRestoreTests`.
@MainActor
struct ChatViewModelInterruptedRestoreTests {
    @Test func `restored interrupted snapshot does not call service and stays retryable`() throws {
        let store = try makeIsolatedStore()
        let bubbleID = UUID()
        let user = Message(sender: .user, text: "A", status: .completed)
        let partial = Message(id: bubbleID, sender: .ai, text: "받다 만", status: .streaming)
        store.save(.init(
            messages: [user, partial],
            expandedMessageIDs: [],
            failedRequests: [bubbleID: .batch(["A"])],
        ))

        let service = CountingChatService()
        let restored = ChatViewModel(service: service, store: store, characterDelay: .zero)

        #expect(service.greetingCallCount == 0)
        #expect(service.sendCallCount == 0)
        #expect(restored.messages.count == 2)
        #expect(restored.messages[1].id == bubbleID)
        #expect(restored.messages[1].status == .failed)
        #expect(restored.messages[1].failure == .unknown)
        #expect(restored.canRetry(bubbleID))
    }

    @Test func `restore write-back persists normalized failed state and drops completed residue`() throws {
        let store = try makeIsolatedStore()
        let streamingID = UUID()
        let completedID = UUID()
        store.save(.init(
            messages: [
                Message(id: streamingID, sender: .ai, text: "부분", status: .streaming),
                Message(id: completedID, sender: .ai, text: "완료", status: .completed),
            ],
            expandedMessageIDs: [],
            failedRequests: [
                streamingID: .batch(["A"]),
                completedID: .batch(["B"]),
            ],
        ))

        _ = ChatViewModel(service: CountingChatService(), store: store, characterDelay: .zero)

        let disk = try #require(store.load())
        #expect(disk.messages.contains {
            $0.id == streamingID && $0.status == .failed && $0.failure == .unknown
        })
        #expect(disk.failedRequests?[streamingID] == .batch(["A"]))
        #expect(disk.failedRequests?[completedID] == nil)
        #expect(disk.messages.contains { $0.id == completedID && $0.status == .completed })
    }

    @Test func `map-only anchor is retryable without auto resend`() throws {
        let store = try makeIsolatedStore()
        let anchorID = UUID()
        let user = Message(sender: .user, text: "A", status: .completed)
        store.save(.init(
            messages: [user],
            expandedMessageIDs: [],
            failedRequests: [anchorID: .batch(["A"])],
        ))

        let service = CountingChatService()
        let restored = ChatViewModel(service: service, store: store, characterDelay: .zero)

        #expect(service.greetingCallCount == 0)
        #expect(service.sendCallCount == 0)
        #expect(restored.canRetry(anchorID))
        #expect(restored.messages.contains { $0.id == anchorID && $0.status == .failed })
    }

    @Test func `nil failedRequests loads like empty map without retry`() throws {
        let store = try makeIsolatedStore()
        let streaming = Message(sender: .ai, text: "부분", status: .streaming)
        store.save(.init(
            messages: [streaming],
            expandedMessageIDs: [],
            failedRequests: nil,
        ))

        let restored = ChatViewModel(
            service: CountingChatService(),
            store: store,
            characterDelay: .zero,
        )

        #expect(restored.messages.count == 1)
        #expect(restored.messages[0].status == .completed)
        #expect(!restored.canRetry(restored.messages[0].id))
    }
}
