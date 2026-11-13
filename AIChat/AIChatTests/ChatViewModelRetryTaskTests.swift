@testable import AIChat
import Foundation
import Testing

/// #A2 Task 2 — 재시도 Task 핸들 등록·제거·deinit 일괄 취소.
@MainActor
struct ChatViewModelRetryTaskTests {
    private struct RestoredFailedFixture {
        let viewModel: ChatViewModel
        let failedID: UUID
    }

    /// store 복원으로 greeting Task를 띄우지 않고 실패 말풍선 + 원본 맵만 준비한다.
    private func makeRestoredFailedViewModel(
        service: ChatService,
        userText: String = "A",
        store: ChatHistoryStore? = nil,
    ) throws -> RestoredFailedFixture {
        let store = try store ?? makeIsolatedStore()
        let user = Message(sender: .user, text: userText, status: .completed)
        let failed = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        store.save(.init(
            messages: [user, failed],
            expandedMessageIDs: [],
            failedRequests: [failed.id: .batch([userText])],
        ))
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)
        let failedID = try #require(viewModel.messages.first { $0.status == .failed }?.id)
        return RestoredFailedFixture(viewModel: viewModel, failedID: failedID)
    }

    @Test func `retry while hang tracks the failed message id`() async throws {
        let service = HangingSendWithTerminationCounter()
        let fixture = try makeRestoredFailedViewModel(service: service)
        let viewModel = fixture.viewModel
        let failedID = fixture.failedID

        viewModel.retry(failedID)

        #expect(viewModel.isRetryTaskTracked(failedID))
        #expect(viewModel.retryTaskCountForTesting == 1)
        #expect(await waitUntil { service.activeStreamCount >= 1 })
        // 관측 동안 VM을 붙잡는다 — 여기서 놓으면 deinit cancel이 먼저 돈다.
        #expect(viewModel.isRetryTaskTracked(failedID))
    }

    @Test func `retry success clears the tracked handle`() async throws {
        let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
        let fixture = try makeRestoredFailedViewModel(service: service)
        let viewModel = fixture.viewModel
        let failedID = fixture.failedID

        viewModel.retry(failedID)

        #expect(await waitUntil {
            viewModel.messages.contains {
                $0.sender == .ai && $0.status == .completed && $0.text.contains("A")
            }
                && !viewModel.isRetryTaskTracked(failedID)
                && viewModel.retryTaskCountForTesting == 0
        })
        #expect(!viewModel.isRetryTaskTracked(failedID))
        #expect(viewModel.retryTaskCountForTesting == 0)
    }

    @Test func `retry failure clears the tracked handle`() async throws {
        let service = FailingChatService(error: ChatServiceError.network)
        let fixture = try makeRestoredFailedViewModel(service: service)
        let viewModel = fixture.viewModel
        let failedID = fixture.failedID

        viewModel.retry(failedID)

        #expect(await waitUntil {
            viewModel.messages.contains { $0.sender == .ai && $0.status == .failed }
                && viewModel.retryTaskCountForTesting == 0
        })
        #expect(!viewModel.isRetryTaskTracked(failedID))
        #expect(viewModel.retryTaskCountForTesting == 0)
    }

    @Test func `deinit while hang terminates the send producer`() async throws {
        let service = HangingSendWithTerminationCounter()
        let store = try makeIsolatedStore()
        let user = Message(sender: .user, text: "A", status: .completed)
        let failed = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        store.save(.init(
            messages: [user, failed],
            expandedMessageIDs: [],
            failedRequests: [failed.id: .batch(["A"])],
        ))

        var viewModel: ChatViewModel? = ChatViewModel(
            service: service, store: store, characterDelay: .zero,
        )
        let failedID = try #require(viewModel?.messages.first { $0.status == .failed }?.id)
        viewModel?.retry(failedID)

        #expect(viewModel?.isRetryTaskTracked(failedID) == true)
        #expect(await waitUntil { service.activeStreamCount >= 1 })
        let terminatedBefore = service.terminatedStreamCount

        // 해제 케이스: 외부 소유를 끊어 deinit cancel → 프로듀서 onTermination을 본다.
        // 관측 중 붙잡던 참조를 끊는다. weak self + 핸들 맵이 사이클을 만들면 실패한다.
        viewModel = nil

        #expect(await waitUntil(timeout: .seconds(4)) {
            service.terminatedStreamCount > terminatedBefore
        })
        #expect(service.activeStreamCount == 0)
    }

    @Test func `concurrent retries track both handles then clear them`() async throws {
        let store = try makeIsolatedStore()
        let userA = Message(sender: .user, text: "A", status: .completed)
        let failedA = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        let userB = Message(sender: .user, text: "B", status: .completed)
        let failedB = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        store.save(.init(
            messages: [userA, failedA, userB, failedB],
            expandedMessageIDs: [],
            failedRequests: [failedA.id: .batch(["A"]), failedB.id: .batch(["B"])],
        ))
        // 청크를 천천히 흘려 완료 전에 두 핸들이 동시에 잡히는 틈을 만든다.
        let service = MockChatService(delay: .zero, chunkDelay: .milliseconds(40), includesPrefix: { false })
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)

        viewModel.retry(failedA.id)
        viewModel.retry(failedB.id)

        #expect(viewModel.isRetryTaskTracked(failedA.id))
        #expect(viewModel.isRetryTaskTracked(failedB.id))
        #expect(viewModel.retryTaskCountForTesting == 2)

        #expect(await waitUntil {
            viewModel.messages.contains {
                $0.sender == .ai && $0.status == .completed && $0.text.contains("A")
            }
                && viewModel.messages.contains {
                    $0.sender == .ai && $0.status == .completed && $0.text.contains("B")
                }
                && viewModel.retryTaskCountForTesting == 0
        })
        #expect(!viewModel.isRetryTaskTracked(failedA.id))
        #expect(!viewModel.isRetryTaskTracked(failedB.id))
        #expect(viewModel.retryTaskCountForTesting == 0)
    }
}
