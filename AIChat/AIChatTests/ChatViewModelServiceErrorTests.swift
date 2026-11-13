@testable import AIChat
import Foundation
import Testing

/// 서비스 실패·빈 성공·취소·non-retryable 재시도 no-op 등 ChatViewModel 종료 경로 일반화 검증.
/// timeout 전용 회귀는 ChatViewModelTimeoutTests, canSend 복구는 ChatViewModelTests에 있다.
/// 공용 헬퍼(`makeIsolatedStore`/`waitUntil`)는 ChatViewModelTests.swift에 있다.
@MainActor
struct ChatViewModelServiceErrorTests {
    // MARK: - retryable throw (network / unknown)

    @Test func `network throw keeps empty failed bubble with failure and retryable request`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: FailingChatService(error: ChatServiceError.network),
            store: store,
            characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.last?.sender == .ai)
        #expect(viewModel.messages.last?.text.isEmpty == true)
        #expect(viewModel.messages.last?.failure == .network)

        let failedID = try #require(viewModel.messages.last?.id)
        #expect(viewModel.canRetry(failedID))
        let loaded = try #require(store.load())
        #expect(loaded.failedRequests?[failedID] == .batch(["A"]))
    }

    /// 부분 수신 + typed unknown + multi-chunk(held flush 경로) + failedRequests를 한 시나리오로 고정.
    @Test func `partial then fail keeps concatenated text as unknown with retryable request`() async throws {
        let store = try makeIsolatedStore()
        let service = FailingChatService(
            greeting: .text("hi"),
            // 여러 청크로 나눠 held 문자가 throw 직전에도 보존되는지 같이 본다
            send: [.chunksThenFail(["부", "분"], ChatServiceError.unknown)],
        )
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)
        #expect(await waitUntil { viewModel.messages.first?.status == .completed })

        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        #expect(viewModel.messages.last?.text == "부분")
        #expect(viewModel.messages.last?.status != .completed)
        #expect(viewModel.messages.last?.failure == .unknown)

        let failedID = try #require(viewModel.messages.last?.id)
        #expect(viewModel.canRetry(failedID))
        let loaded = try #require(store.load())
        #expect(loaded.failedRequests?[failedID] == .batch(["A"]))
    }

    @Test func `non ChatServiceError maps to unknown keeps empty bubble and is retryable`() async throws {
        struct DummyError: Error {}
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: FailingChatService(error: DummyError()),
            store: store,
            characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.last?.sender == .ai)
        #expect(viewModel.messages.last?.text.isEmpty == true)
        #expect(viewModel.messages.last?.failure == .unknown)

        let failedID = try #require(viewModel.messages.last?.id)
        #expect(viewModel.canRetry(failedID))
        let loaded = try #require(store.load())
        #expect(loaded.failedRequests?[failedID] == .batch(["A"]))
    }

    // MARK: - non-retryable (decoding / unauthorized)

    @Test func `decoding throw sets failure but does not record failedRequests`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: FailingChatService(error: ChatServiceError.decoding),
            store: store,
            characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        #expect(viewModel.messages.last?.failure == .decoding)

        let failedID = try #require(viewModel.messages.last?.id)
        #expect(!viewModel.canRetry(failedID))
        let loaded = try #require(store.load())
        // non-retryable 키는 기록되지 않는다 — 복원 후에도 죽은 재시도 버튼이 생기지 않게
        let recorded = loaded.failedRequests ?? [:]
        #expect(recorded[failedID] == nil)
        #expect(recorded.isEmpty)
    }

    @Test func `unauthorized retry is a no-op`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: FailingChatService(error: ChatServiceError.unauthorized),
            store: store,
            characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        #expect(viewModel.messages.last?.failure == .unauthorized)
        let failedID = try #require(viewModel.messages.last?.id)
        #expect(!viewModel.canRetry(failedID))
        let before = viewModel.messages.map(\.id)

        viewModel.retry(failedID)

        #expect(viewModel.messages.map(\.id) == before)
        #expect(viewModel.messages.last?.status == .failed)
        #expect(viewModel.messages.last?.failure == .unauthorized)
    }

    // MARK: - empty success stream

    @Test func `empty success stream becomes failed unknown and is retryable`() async throws {
        let store = try makeIsolatedStore()
        let service = FailingChatService(
            greeting: .emptySuccess,
            send: [.emptySuccess],
        )
        // messages 미지정 → 인사말 스트림이 빈 성공으로 끝난다
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)
        #expect(await waitUntil { viewModel.messages.first?.status == .failed })
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].failure == .unknown)
        #expect(viewModel.messages[0].text.isEmpty)

        let greetingID = viewModel.messages[0].id
        #expect(viewModel.canRetry(greetingID))
        let greetingLoaded = try #require(store.load())
        #expect(greetingLoaded.failedRequests?[greetingID] == .greeting)

        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil {
            viewModel.messages.count == 3 && viewModel.messages.last?.status == .failed
        })
        #expect(viewModel.messages.last?.failure == .unknown)
        let sendID = try #require(viewModel.messages.last?.id)
        let sendLoaded = try #require(store.load())
        #expect(sendLoaded.failedRequests?[sendID] == .batch(["A"]))
    }

    // MARK: - cancel is not failure

    @Test func `cancel mid-stream is not failed and leaves no failure`() async throws {
        // 느린 Mock으로 스트리밍 중 취소. 실패 스텁이 아니라 실제 취소 경로.
        let service = MockChatService(delay: .zero, chunkDelay: .milliseconds(20), includesPrefix: { false })
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            service: service, store: store, characterDelay: .milliseconds(5),
        )
        #expect(await waitUntil { viewModel.messages.first?.status == .completed })

        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { viewModel.messages.contains { $0.status == .streaming } })

        viewModel.inputText = "B"
        viewModel.send()

        #expect(await waitUntil {
            viewModel.messages.filter { $0.sender == .ai }.allSatisfy { $0.status == .completed }
        })
        #expect(viewModel.messages.filter { $0.sender == .ai }.allSatisfy { $0.failure == nil })
        #expect(viewModel.messages.allSatisfy { $0.status != .failed })
    }

    // MARK: - retry after retryable failure

    @Test func `retry after network failure creates a new bubble without failure`() async throws {
        let service = ToggleFailThenSucceedService()
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            service: service, store: store, characterDelay: .zero,
        )
        #expect(await waitUntil { viewModel.messages.first?.status == .completed })

        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { viewModel.messages.last?.status == .failed })
        let failedID = try #require(viewModel.messages.last?.id)
        #expect(viewModel.messages.last?.failure == .network)

        viewModel.retry(failedID)

        #expect(viewModel.messages.map(\.sender) == [.ai, .user])
        #expect(await waitUntil {
            viewModel.messages.last?.status == .completed
                && viewModel.messages.last?.id != failedID
                && viewModel.messages.last?.text.contains("재시도 성공") == true
        })
        #expect(viewModel.messages.last?.failure == nil)
        #expect(!viewModel.canRetry(failedID))
    }
}

/// 실패 상태 영속 복원 경로만 분리 — 본 스위트 type_body_length 한도 때문.
@MainActor
struct ChatViewModelServiceErrorRestoreTests {
    @Test func `restored retryable failure with failedRequests can be retried`() async throws {
        let store = try makeIsolatedStore()
        let user = Message(sender: .user, text: "A", status: .completed)
        let failed = Message(sender: .ai, text: "", status: .failed, failure: .network)
        store.save(.init(
            messages: [user, failed],
            expandedMessageIDs: [],
            failedRequests: [failed.id: .batch(["A"])],
        ))
        let restored = ChatViewModel(
            service: MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false }),
            store: store,
            characterDelay: .zero,
        )

        #expect(restored.canRetry(failed.id))
        restored.retry(failed.id)

        #expect(restored.messages.map(\.id) == [user.id])
        #expect(await waitUntil {
            restored.messages.count == 2 && restored.messages.last?.status == .completed
        })
        #expect(restored.messages.last?.failure == nil)
        #expect(!restored.canRetry(failed.id))
    }

    @Test func `restored non-retryable failure has no failedRequests and retry is no-op`() throws {
        let store = try makeIsolatedStore()
        let user = Message(sender: .user, text: "A", status: .completed)
        let failed = Message(sender: .ai, text: "", status: .failed, failure: .decoding)
        // non-retryable은 저장 시 failedRequests에 안 실리는 게 정상 — 빈 맵으로 복원
        store.save(.init(
            messages: [user, failed],
            expandedMessageIDs: [],
            failedRequests: [:],
        ))
        let restored = ChatViewModel(
            service: MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false }),
            store: store,
            characterDelay: .zero,
        )

        let before = restored.messages.map(\.id)
        #expect(!restored.canRetry(failed.id))
        restored.retry(failed.id)

        #expect(restored.messages.map(\.id) == before)
        #expect(restored.messages.last?.status == .failed)
        #expect(restored.messages.last?.failure == .decoding)
        let recorded = store.load()?.failedRequests ?? [:]
        #expect(recorded.isEmpty)
    }

    /// 유형은 retryable인데 원본 맵에 없으면 버튼을 켜면 안 된다 — `canRetry`가 유형 정책과 분리됐는지 고정.
    @Test func `canRetry is false for orphan retryable failure without failedRequests`() throws {
        let store = try makeIsolatedStore()
        let failed = Message(sender: .ai, text: "", status: .failed, failure: .network)
        store.save(.init(
            messages: [failed],
            expandedMessageIDs: [],
            failedRequests: [:],
        ))
        let restored = ChatViewModel(
            service: MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false }),
            store: store,
            characterDelay: .zero,
        )

        #expect(MessageFailureCopy.isRetryable(for: failed))
        #expect(!restored.canRetry(failed.id))
    }
}
