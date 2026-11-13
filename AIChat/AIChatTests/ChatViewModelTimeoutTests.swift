@testable import AIChat
import Foundation
import Testing

/// 첫 청크(TTFT)가 오기 한참 전에 무응답 감시에 걸리는 서비스. `delay`가 길어도 감시가 끊으면
/// 프로듀서까지 연쇄 취소되므로 테스트가 `delay`만큼 기다리지 않는다.
private func makeStallingService(includesPrefix: Bool = false) -> MockChatService {
    MockChatService(
        delay: .seconds(5), chunkDelay: .zero, timeoutInterval: 0.2, includesPrefix: { includesPrefix },
    )
}

/// 지연 없이 끝까지 흘러 재시도가 성공하는 서비스.
private func makeInstantService() -> MockChatService {
    MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
}

/// 무응답(timeout) 확정과 재시도만 다루는 스위트. 공용 헬퍼(`makeIsolatedStore`/`waitUntil`)는 ChatViewModelTests.swift에 있다.
@MainActor
struct ChatViewModelTimeoutTests {
    @Test func `a response that times out before its first character keeps a failed bubble`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = try ChatViewModel(
            messages: [], service: makeStallingService(), store: store, characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        // 한 글자도 못 받았다고 지워버리면 실패가 흔적 없이 사라진다 — 말풍선이 남아야 재시도 지점이 생긴다
        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.last?.sender == .ai)
        #expect(viewModel.messages.last?.text.isEmpty == true)
        #expect(viewModel.messages.last?.failure == .timeout)
        let failedID = try #require(viewModel.messages.last?.id)
        #expect(try #require(store.load()).failedRequests?[failedID] == .batch(["A"]))
    }

    @Test func `a response that times out mid-stream keeps the text it already received`() async throws {
        // 첫 청크는 바로 오고 그 다음 청크가 timeout보다 한참 늦게 온다 — 부분 수신 상태에서 끊긴다
        let service = MockChatService(
            delay: .zero, chunkDelay: .seconds(5), timeoutInterval: 0.2, includesPrefix: { false },
        )
        let viewModel = try ChatViewModel(
            messages: [], service: service, store: makeIsolatedStore(), characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        #expect(viewModel.messages.last?.text.isEmpty == false)
        #expect(viewModel.messages.last?.failure == .timeout)
    }

    @Test func `canSend recovers after a timeout`() async throws {
        let viewModel = try ChatViewModel(
            messages: [], service: makeStallingService(), store: makeIsolatedStore(), characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        viewModel.inputText = "B"
        viewModel.send()

        viewModel.inputText = "C"
        #expect(!viewModel.canSend)

        #expect(await waitUntil { viewModel.canSend })
    }

    @Test func `a timed out first stream stops the remaining bubbles`() async throws {
        // 프리픽스 + 답변 2개 스트림 중 앞 것이 끊긴다 — 답변 말풍선까지 만들면 실패한 대화가 이어진 것처럼 보인다
        let viewModel = try ChatViewModel(
            messages: [], service: makeStallingService(includesPrefix: true), store: makeIsolatedStore(),
            characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        let grew = await waitUntil(timeout: .milliseconds(300)) { viewModel.messages.count > 2 }
        #expect(!grew)
    }

    @Test func `retry replaces the failed bubble without duplicating the user message`() async throws {
        let viewModel = try ChatViewModel(
            messages: [], service: makeStallingService(), store: makeIsolatedStore(), characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        let failedID = try #require(viewModel.messages.last?.id)

        viewModel.retry(failedID)

        // 실패 말풍선은 즉시 사라지고, 사용자 메시지는 이미 화면에 있으므로 다시 쌓이지 않는다
        #expect(viewModel.messages.map(\.sender) == [.user])
        #expect(await waitUntil { viewModel.messages.count == 2 && viewModel.messages.last?.id != failedID })
        #expect(viewModel.messages.filter { $0.sender == .user }.count == 1)
    }

    @Test func `a timed out greeting stays as a failed bubble and can be retried`() async throws {
        let viewModel = try ChatViewModel(
            service: makeStallingService(), store: makeIsolatedStore(), characterDelay: .zero,
        )
        #expect(await waitUntil { viewModel.messages.first?.status == .failed })
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.failure == .timeout)
        let failedID = try #require(viewModel.messages.first?.id)

        viewModel.retry(failedID)

        #expect(viewModel.messages.isEmpty)
        #expect(await waitUntil { viewModel.messages.count == 1 && viewModel.messages[0].id != failedID })
        #expect(viewModel.messages[0].sender == .ai)
        #expect(viewModel.messages[0].failure == nil)
    }

    @Test func `failed bubbles stay failed after a restore`() throws {
        let store = try makeIsolatedStore()
        // 빈 실패(TTFT timeout)와 부분 수신 실패 둘 다 — 빈 쪽이 "빈 말풍선 폐기"에 쓸려나가면 재시도 지점이 사라진다
        let empty = Message(sender: .ai, text: "", status: .failed)
        let partial = Message(sender: .ai, text: "받다 만 텍스트", status: .failed)
        store.save(.init(messages: [empty, partial], expandedMessageIDs: []))

        let restored = ChatViewModel(store: store, characterDelay: .zero)

        #expect(restored.messages.map(\.id) == [empty.id, partial.id])
        #expect(restored.messages.map(\.status) == [.failed, .failed])
        #expect(restored.messages.map(\.text) == ["", "받다 만 텍스트"])
    }

    @Test func `a restored failed bubble can still be retried`() async throws {
        let store = try makeIsolatedStore()
        let user = Message(sender: .user, text: "A", status: .completed)
        let failed = Message(sender: .ai, text: "", status: .failed)
        store.save(.init(
            messages: [user, failed], expandedMessageIDs: [], failedRequests: [failed.id: .batch(["A"])],
        ))
        let restored = ChatViewModel(service: makeInstantService(), store: store, characterDelay: .zero)

        restored.retry(failed.id)

        #expect(restored.messages.map(\.id) == [user.id])
        #expect(await waitUntil { restored.messages.count == 2 && restored.messages.last?.status == .completed })
        #expect(restored.messages.filter { $0.sender == .user }.count == 1)
    }

    /// 재요청은 그 요청이 만들던 말풍선을 **전부** 다시 만든다 — 앞서 성공했던 프리픽스를 남겨두면 두 번 뜬다.
    @Test func `retrying a batch also clears the bubbles that request already produced`() async throws {
        let store = try makeIsolatedStore()
        let user = Message(sender: .user, text: "A", status: .completed)
        let prefix = Message(sender: .ai, text: "좋은 질문이에요!", status: .completed)
        let failed = Message(sender: .ai, text: "", status: .failed)
        store.save(.init(
            messages: [user, prefix, failed], expandedMessageIDs: [],
            failedRequests: [failed.id: .batch(["A"])],
        ))
        let restored = ChatViewModel(service: makeInstantService(), store: store, characterDelay: .zero)

        restored.retry(failed.id)

        // 실패 말풍선뿐 아니라 같은 요청이 만든 프리픽스까지 사라져야 한다
        #expect(restored.messages.map(\.id) == [user.id])
        #expect(await waitUntil { restored.messages.last?.status == .completed })
        #expect(!restored.messages.contains { $0.id == prefix.id })
    }

    /// 실패 말풍선은 화면에 계속 남으므로, 새 응답이 흐르는 도중에 위쪽 옛 실패를 재시도할 수 있다.
    @Test func `retrying an old failure does not cut the response that is streaming`() async throws {
        let store = try makeIsolatedStore()
        let failed = Message(sender: .ai, text: "", status: .failed)
        store.save(.init(
            messages: [failed], expandedMessageIDs: [], failedRequests: [failed.id: .greeting],
        ))
        // 청크가 천천히 흘러 스트리밍 도중에 재시도를 끼워 넣을 틈이 있다
        let service = MockChatService(delay: .zero, chunkDelay: .milliseconds(30), includesPrefix: { false })
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)

        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { viewModel.messages.last?.status == .streaming })

        viewModel.retry(failed.id)

        // 재시도가 진행 중 응답을 취소했다면 이 말풍선은 받다 만 텍스트로 확정돼 완전한 답변이 나오지 않는다
        #expect(await waitUntil { viewModel.messages.contains { $0.text == "'A'라고 하셨네요." } })
    }

    /// 실패 말풍선이 여러 개 남아 있을 수 있고, 각각은 독립된 요청이다 — 하나를 재시도한다고 다른 하나의
    /// 재시도가 취소되면 사용자는 누른 적 없는 요청이 조용히 사라지는 걸 보게 된다.
    @Test func `retrying one failure does not cancel another failure's retry`() async throws {
        let store = try makeIsolatedStore()
        let userA = Message(sender: .user, text: "A", status: .completed)
        let failedA = Message(sender: .ai, text: "", status: .failed)
        let userB = Message(sender: .user, text: "B", status: .completed)
        let failedB = Message(sender: .ai, text: "", status: .failed)
        store.save(.init(
            messages: [userA, failedA, userB, failedB], expandedMessageIDs: [],
            failedRequests: [failedA.id: .batch(["A"]), failedB.id: .batch(["B"])],
        ))
        // 첫 재시도가 아직 흐르는 동안 두 번째를 누를 수 있을 만큼 천천히 도착한다
        let service = MockChatService(delay: .zero, chunkDelay: .milliseconds(30), includesPrefix: { false })
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)

        viewModel.retry(failedA.id)
        #expect(await waitUntil { viewModel.messages.contains { $0.status == .streaming } })
        viewModel.retry(failedB.id)

        // 두 재시도가 모두 끝까지 흘러야 한다 — 한쪽이 취소되면 그 답변이 영영 안 나온다
        #expect(await waitUntil { viewModel.messages.contains { $0.text == "'A'라고 하셨네요." } })
        #expect(await waitUntil { viewModel.messages.contains { $0.text == "'B'라고 하셨네요." } })
    }

    /// materialize된 맵 전용 앵커도 retry 경로가 살아 있다(정규화 자체는 ChatHistoryRestoreTests).
    @Test func `materialized orphan map key can be retried`() async throws {
        let store = try makeIsolatedStore()
        let stray = UUID()
        let completed = Message(sender: .ai, text: "완료된 대화", status: .completed)
        store.save(.init(
            messages: [completed],
            expandedMessageIDs: [],
            failedRequests: [stray: .batch(["A"])],
        ))

        let restored = ChatViewModel(service: makeInstantService(), store: store, characterDelay: .zero)

        #expect(restored.canRetry(stray))
        restored.retry(stray)

        #expect(await waitUntil {
            restored.messages.contains { $0.sender == .ai && $0.status == .completed && $0.text.contains("A") }
        })
    }
}
