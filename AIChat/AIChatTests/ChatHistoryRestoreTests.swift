@testable import AIChat
import Foundation
import Testing

/// 복원 정규화 순수 함수. ViewModel/네트워크 없이 messages+맵 outcome만 본다.
struct ChatHistoryRestoreTests {
    @Test func `map-backed streaming becomes failed unknown and keeps map`() {
        let id = UUID()
        let streaming = Message(id: id, sender: .ai, text: "받다 만", status: .streaming)
        let result = ChatHistoryRestore.restore(
            messages: [streaming],
            failedRequests: [id: .batch(["A"])],
        )

        #expect(result.messages.count == 1)
        #expect(result.messages[0].id == id)
        #expect(result.messages[0].text == "받다 만")
        #expect(result.messages[0].status == .failed)
        #expect(result.messages[0].failure == .unknown)
        #expect(result.failedRequests[id] == .batch(["A"]))
    }

    @Test func `map-backed empty pending becomes empty failed`() {
        let id = UUID()
        let pending = Message(id: id, sender: .ai, text: "", status: .pending)
        let result = ChatHistoryRestore.restore(
            messages: [pending],
            failedRequests: [id: .batch(["A"])],
        )

        #expect(result.messages.count == 1)
        #expect(result.messages[0].id == id)
        #expect(result.messages[0].text.isEmpty)
        #expect(result.messages[0].status == .failed)
        #expect(result.messages[0].failure == .unknown)
        #expect(result.failedRequests[id] == .batch(["A"]))
    }

    @Test func `map key without bubble materializes empty failed anchor`() throws {
        let anchor = UUID()
        let user = Message(sender: .user, text: "A", status: .completed)
        let result = ChatHistoryRestore.restore(
            messages: [user],
            failedRequests: [anchor: .batch(["A"])],
        )

        #expect(result.messages.contains { $0.id == user.id })
        let material = try #require(result.messages.first { $0.id == anchor })
        #expect(material.sender == .ai)
        #expect(material.status == .failed)
        #expect(material.failure == .unknown)
        #expect(material.text.isEmpty)
        #expect(result.failedRequests[anchor] == .batch(["A"]))
    }

    @Test func `orphan unfinished text settles completed and empty orphan is dropped`() {
        let partial = Message(sender: .ai, text: "부분", status: .streaming)
        let empty = Message(sender: .ai, text: "", status: .pending)
        let result = ChatHistoryRestore.restore(
            messages: [empty, partial],
            failedRequests: [:],
        )

        #expect(result.messages.count == 1)
        #expect(result.messages[0].text == "부분")
        #expect(result.messages[0].status == .completed)
        #expect(result.messages[0].failure == nil)
        #expect(result.failedRequests.isEmpty)
    }

    @Test func `completed residue drops map entry and keeps message`() {
        let id = UUID()
        let completed = Message(id: id, sender: .ai, text: "완료", status: .completed)
        let result = ChatHistoryRestore.restore(
            messages: [completed],
            failedRequests: [id: .batch(["A"])],
        )

        #expect(result.messages.count == 1)
        #expect(result.messages[0].id == id)
        #expect(result.messages[0].status == .completed)
        #expect(result.failedRequests[id] == nil)
    }

    @Test func `existing failed keeps original failure classification`() {
        let id = UUID()
        let failed = Message(id: id, sender: .ai, text: "", status: .failed, failure: .timeout)
        let result = ChatHistoryRestore.restore(
            messages: [failed],
            failedRequests: [id: .greeting],
        )

        #expect(result.messages[0].failure == .timeout)
        #expect(result.messages[0].status == .failed)
        #expect(result.failedRequests[id] == .greeting)
    }

    @Test func `map-less pending is dropped even when other map keys materialize`() {
        let orphanPending = UUID()
        let stray = UUID()
        let result = ChatHistoryRestore.restore(
            messages: [Message(id: orphanPending, sender: .ai, text: "", status: .pending)],
            failedRequests: [stray: .batch(["X"])],
        )

        #expect(!result.messages.contains { $0.id == orphanPending })
        #expect(result.messages.contains { $0.id == stray && $0.status == .failed })
        #expect(result.failedRequests[stray] == .batch(["X"]))
        #expect(result.failedRequests[orphanPending] == nil)
    }
}
