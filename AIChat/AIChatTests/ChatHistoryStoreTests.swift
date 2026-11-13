@testable import AIChat
import Foundation
import Testing

/// failedRequests가 생기기 전의 저장 형식. 그 시절 JSON을 만들어내는 게 목적이라 PersistedState를 재사용할 수 없다.
private struct LegacyPersistedState: Codable {
    var messages: [Message]
    var expandedMessageIDs: Set<UUID>
}

struct ChatHistoryStoreTests {
    private func makeIsolatedStore() throws -> ChatHistoryStore {
        try ChatHistoryStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
    }

    @Test func `load returns nil when nothing was saved`() throws {
        let store = try makeIsolatedStore()

        #expect(store.load() == nil)
    }

    @Test func `save then load round-trips messages and expanded IDs`() throws {
        let store = try makeIsolatedStore()
        let message = Message(sender: .ai, text: "안녕하세요", status: .completed)
        let state = ChatHistoryStore.PersistedState(messages: [message], expandedMessageIDs: [message.id])

        store.save(state)
        let loaded = store.load()

        #expect(loaded?.messages == [message])
        #expect(loaded?.expandedMessageIDs == [message.id])
    }

    @Test func `save then load round-trips failed requests`() throws {
        let store = try makeIsolatedStore()
        let message = Message(sender: .ai, text: "", status: .failed)
        let state = ChatHistoryStore.PersistedState(
            messages: [message], expandedMessageIDs: [], failedRequests: [message.id: .batch(["A", "B"])],
        )

        store.save(state)

        #expect(store.load()?.failedRequests == [message.id: .batch(["A", "B"])])
    }

    /// failedRequests가 비옵셔널이면 이 저장분이 통째로 디코딩에 실패해 대화 이력이 날아간다.
    @Test func `state saved before failedRequests existed still loads`() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = ChatHistoryStore(defaults: defaults)
        let message = Message(sender: .ai, text: "예전 이력", status: .completed)
        let legacy = try JSONEncoder()
            .encode(LegacyPersistedState(messages: [message], expandedMessageIDs: [message.id]))
        // private static let key와 같은 값 — 테스트에서 참조할 수 없어 문자열을 그대로 쓴다
        defaults.set(legacy, forKey: "ChatHistoryStore.persistedState")

        let loaded = store.load()

        #expect(loaded?.messages == [message])
        #expect(loaded?.expandedMessageIDs == [message.id])
        #expect(loaded?.failedRequests == nil)
    }

    @Test func `two isolated stores do not leak state into each other`() throws {
        let first = try makeIsolatedStore()
        let second = try makeIsolatedStore()
        let message = Message(sender: .user, text: "hi", status: .completed)

        first.save(ChatHistoryStore.PersistedState(messages: [message], expandedMessageIDs: []))

        #expect(second.load() == nil)
    }

    @Test func `save then load round-trips message failure`() throws {
        let store = try makeIsolatedStore()
        let message = Message(sender: .ai, text: "", status: .failed, failure: .decoding)
        let state = ChatHistoryStore.PersistedState(
            messages: [message],
            expandedMessageIDs: [],
            failedRequests: nil,
        )

        store.save(state)
        let loaded = store.load()

        #expect(loaded?.messages == [message])
        #expect(loaded?.messages.first?.failure == .decoding)
    }
}
