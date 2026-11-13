@testable import AIChat
import Foundation
import Testing

/// 런타임 in-flight 맵 기록·승격·성공 시 제거.
@MainActor
struct ChatViewModelInFlightPersistenceTests {
    @Test func `send records batch in failedRequests before response finishes`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: HangingChatService(),
            store: store,
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil {
            (store.load()?.failedRequests ?? [:]).values.contains(.batch(["A"]))
        })
        let loaded = try #require(store.load())
        #expect(loaded.messages.contains { $0.sender == .user && $0.text == "A" })
    }

    @Test func `second send in same batch updates map to full batch with single entry`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: HangingChatService(),
            store: store,
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil {
            (store.load()?.failedRequests ?? [:]).values.contains(.batch(["A"]))
        })

        viewModel.inputText = "B"
        viewModel.send()

        #expect(await waitUntil {
            let map = store.load()?.failedRequests ?? [:]
            return map.count == 1 && map.values.contains(.batch(["A", "B"]))
        })
    }

    @Test func `in-flight streaming snapshot restores as failed with retry and no auto resend`() async throws {
        let store = try makeIsolatedStore()
        let service = SlowChunkChatService(chunks: ["가", "나", "다", "라"], chunkDelay: .milliseconds(30))
        let viewModel = ChatViewModel(
            messages: [],
            service: service,
            store: store,
            characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil {
            guard let messages = store.load()?.messages else { return false }
            return messages.contains {
                $0.sender == .ai && !$0.text.isEmpty && ($0.status == .streaming || $0.status == .pending)
            }
        })
        #expect(await waitUntil {
            let map = store.load()?.failedRequests ?? [:]
            return !map.isEmpty
        })

        let counter = CountingChatService()
        let restored = ChatViewModel(service: counter, store: store, characterDelay: .zero)

        #expect(counter.greetingCallCount == 0)
        #expect(counter.sendCallCount == 0)
        let failed = try #require(restored.messages.last { $0.sender == .ai })
        #expect(failed.status == .failed)
        #expect(failed.failure == .unknown)
        #expect(!failed.text.isEmpty)
        #expect(restored.canRetry(failed.id))
        #expect(restored.messages.filter { $0.sender == .user && $0.text == "A" }.count == 1)
    }

    @Test func `successful send clears failedRequests so restore has no retry`() async throws {
        let store = try makeIsolatedStore()
        let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
        let viewModel = ChatViewModel(
            messages: [],
            service: service,
            store: store,
            characterDelay: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil {
            viewModel.messages.last?.status == .completed && viewModel.messages.last?.sender == .ai
        })
        let map = store.load()?.failedRequests ?? [:]
        #expect(map.isEmpty)

        let restored = ChatViewModel(
            service: CountingChatService(),
            store: store,
            characterDelay: .zero,
        )
        #expect(restored.messages.last?.status == .completed)
        if let last = restored.messages.last {
            #expect(!restored.canRetry(last.id))
        }
    }

    @Test func `retry after restored in-flight failure does not duplicate user message`() async throws {
        let store = try makeIsolatedStore()
        let anchor = UUID()
        let user = Message(sender: .user, text: "A", status: .completed)
        store.save(.init(
            messages: [user],
            expandedMessageIDs: [],
            failedRequests: [anchor: .batch(["A"])],
        ))

        let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
        let restored = ChatViewModel(service: service, store: store, characterDelay: .zero)
        let failedID = try #require(restored.messages.first { $0.status == .failed }?.id)
        #expect(restored.canRetry(failedID))

        restored.retry(failedID)

        #expect(await waitUntil {
            restored.messages.last?.status == .completed && restored.messages.last?.sender == .ai
        })
        #expect(restored.messages.filter { $0.sender == .user }.count == 1)
        let leftovers = store.load()?.failedRequests ?? [:]
        #expect(leftovers.isEmpty)
    }

    /// 동시 retry가 서로의 in-flight 맵을 훔치면, 한쪽 성공 직후 다른 쪽 키가 사라져 복원 재시도가 깨진다.
    @Test func `concurrent retries keep independent map entries while both stream`() async throws {
        let store = try makeIsolatedStore()
        let failedA = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        let failedB = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        let userA = Message(sender: .user, text: "A", status: .completed)
        let userB = Message(sender: .user, text: "B", status: .completed)
        store.save(.init(
            messages: [userA, failedA, userB, failedB],
            expandedMessageIDs: [],
            failedRequests: [failedA.id: .batch(["A"]), failedB.id: .batch(["B"])],
        ))
        let service = MockChatService(delay: .zero, chunkDelay: .milliseconds(40), includesPrefix: { false })
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)

        viewModel.retry(failedA.id)
        #expect(await waitUntil {
            viewModel.messages.contains { $0.status == .streaming || $0.status == .pending }
        })
        viewModel.retry(failedB.id)

        // 둘 다 흐르는 동안 스냅샷에 배치 원본이 둘 다 남아 있어야 한다(키 도난 방지).
        #expect(await waitUntil {
            let values = Array((store.load()?.failedRequests ?? [:]).values)
            return values.contains(.batch(["A"])) && values.contains(.batch(["B"]))
        })

        #expect(await waitUntil {
            viewModel.messages.contains {
                $0.sender == .ai && $0.status == .completed && $0.text.contains("A")
            }
                && viewModel.messages.contains {
                    $0.sender == .ai && $0.status == .completed && $0.text.contains("B")
                }
        })
        #expect(await waitUntil { (store.load()?.failedRequests ?? [:]).isEmpty })
    }

    /// 디바운스로 이전 run이 취소돼도 맵에는 최신 배치 하나만 남고, 취소 말풍선은 실패로 굳지 않는다.
    @Test func `debounce cancel keeps single latest batch entry and no failed bubbles`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: HangingChatService(),
            store: store,
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil {
            (store.load()?.failedRequests ?? [:]).values.contains(.batch(["A"]))
        })
        // 첫 run이 말풍선으로 승격될 때까지 기다려 취소 시 키 제거 경로를 탄다.
        #expect(await waitUntil {
            store.load()?.messages.contains { $0.sender == .ai && $0.status == .pending } == true
        })

        viewModel.inputText = "B"
        viewModel.send()

        #expect(await waitUntil {
            let map = store.load()?.failedRequests ?? [:]
            return map.count == 1 && map.values.contains(.batch(["A", "B"]))
        })
        #expect(viewModel.messages.allSatisfy { $0.status != .failed })
        #expect(viewModel.messages.filter { $0.sender == .user }.map(\.text) == ["A", "B"])
    }

    @Test func `greeting in-flight records greeting original until success clears it`() async throws {
        let hangStore = try makeIsolatedStore()
        // greeting Task는 [weak self] — in-flight 관측 동안 VM을 붙잡아 둔다(즉시 해제되면 deinit cancel).
        let hangingVM = ChatViewModel(
            service: HangingChatService(), store: hangStore, characterDelay: .zero,
        )
        #expect(await waitUntil {
            // hangingVM을 클로저에서 읽어 수명을 폴링 구간까지 연장한다.
            _ = hangingVM.messages.count
            return (hangStore.load()?.failedRequests ?? [:]).values.contains(.greeting)
        })

        let okStore = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            service: MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false }),
            store: okStore,
            characterDelay: .zero,
        )
        #expect(await waitUntil(timeout: .seconds(4)) {
            viewModel.messages.first?.status == .completed
                && (okStore.load()?.failedRequests ?? [:]).isEmpty
        })
    }
}
