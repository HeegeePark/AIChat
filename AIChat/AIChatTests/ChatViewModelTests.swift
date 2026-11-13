@testable import AIChat
import Foundation
import Testing

/// internal: 같은 헬퍼를 ChatViewModelTimeoutTests(별도 파일)도 쓴다.
func makeIsolatedStore() throws -> ChatHistoryStore {
    try ChatHistoryStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
}

/// 지연 없이 스트리밍하는 서비스. 인사말·응답이 즉시 흘러 테스트가 실제 타이핑 시간을 안 먹는다.
private func makeInstantService(includesPrefix: Bool = false) -> MockChatService {
    MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { includesPrefix })
}

/// 고정 `sleep`은 부하 걸린 머신(UI 테스트 병렬 실행 등)에서 예산을 넘겨 깨진다 — 조건이 참이 될 때까지 재시도한다.
/// 성공하면 즉시 반환하므로 상한을 넉넉히 잡아도 비용이 없다.
/// internal: 같은 헬퍼를 ChatViewModelTimeoutTests(별도 파일)도 쓴다.
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// 인사말 스트리밍이 끝난 상태의 ViewModel — 이후 단언이 인사말 진행 상황에 좌우되지 않게 한다.
@MainActor
private func makeSettledViewModel(
    service: ChatService? = nil,
    store: ChatHistoryStore? = nil,
    debounceInterval: Duration = .zero,
) async throws -> ChatViewModel {
    let viewModel = try ChatViewModel(
        service: service ?? makeInstantService(), store: store ?? makeIsolatedStore(),
        characterDelay: .zero,
        debounceInterval: debounceInterval,
    )
    _ = await waitUntil { viewModel.messages.first?.status == .completed }
    return viewModel
}

@MainActor
struct ChatViewModelTests {
    @Test func `greeting is streamed in as the initial message`() async throws {
        let viewModel = try await makeSettledViewModel()

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].sender == .ai)
        #expect(!viewModel.messages[0].text.isEmpty)
        #expect(viewModel.messages[0].status == .completed)
    }

    @Test func `send appends the user message immediately and clears input`() async throws {
        let viewModel = try await makeSettledViewModel()
        viewModel.inputText = "안녕하세요"

        viewModel.send()

        #expect(viewModel.messages.last?.text == "안녕하세요")
        #expect(viewModel.messages.last?.sender == .user)
        #expect(viewModel.inputText.isEmpty)
    }

    @Test func `canSend becomes false once two messages are pending a response`() throws {
        // 기본 지연(1.2초)이라 테스트가 끝날 때까지 응답이 도착하지 않는다 — 대기 배치가 유지된다
        let viewModel = try ChatViewModel(store: makeIsolatedStore())
        viewModel.inputText = "A"
        viewModel.send()
        viewModel.inputText = "B"
        viewModel.send()
        viewModel.inputText = "C"

        #expect(!viewModel.canSend)
    }

    @Test func `hasPendingSendBatch is true while a batch awaits response and false after settle`() async throws {
        let viewModel = try await makeSettledViewModel()
        #expect(!viewModel.hasPendingSendBatch)

        viewModel.inputText = "A"
        viewModel.send()
        #expect(viewModel.hasPendingSendBatch)

        viewModel.inputText = "B"
        viewModel.send()
        #expect(viewModel.hasPendingSendBatch)

        #expect(await waitUntil { !viewModel.hasPendingSendBatch })
        #expect(!viewModel.hasPendingSendBatch)
    }

    @Test func `single send eventually appends one streamed AI response`() async throws {
        let viewModel = try await makeSettledViewModel()
        viewModel.inputText = "SwiftUI 텍스트 측정"

        viewModel.send()

        // 인사말 + 사용자 메시지 + AI 응답. 말풍선은 글자가 차기 전(.pending)에 먼저 생기므로
        // 개수만 보고 텍스트를 단언하면 경합한다 — 스트리밍이 끝난 것까지 기다린다
        #expect(await waitUntil { viewModel.messages.count == 3 && viewModel.messages.last?.status == .completed })
        #expect(viewModel.messages.last?.sender == .ai)
        #expect(viewModel.messages.last?.text.contains("SwiftUI 텍스트 측정") == true)
    }

    @Test func `two rapid sends are batched into a single AI response`() async throws {
        // includesPrefix 고정 — 랜덤 프리픽스 말풍선이 끼면 개수 단언이 흔들린다.
        let viewModel = try await makeSettledViewModel(
            service: MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false }),
        )

        viewModel.inputText = "A"
        viewModel.send()
        viewModel.inputText = "B"
        viewModel.send()

        // 배치 한 번: 마지막 AI가 A·B를 모두 반영. (취소된 빈 말풍선 제거 후 개수는 인사+유저2+AI1)
        #expect(await waitUntil(timeout: .seconds(4)) {
            let users = viewModel.messages.filter { $0.sender == .user }
            let last = viewModel.messages.last
            return users.count == 2
                && last?.sender == .ai
                && last?.status == .completed
                && (last?.text.contains("A") == true)
                && (last?.text.contains("B") == true)
        })
        #expect(viewModel.messages.filter { $0.sender == .user }.map(\.text) == ["A", "B"])
    }

    @Test func `urls newlines and flag emoji survive streaming intact`() async throws {
        let viewModel = try await makeSettledViewModel()
        let sent = "https://example.com/a?b=1&c=2\n둘째 줄\t탭 🇰🇷👍🏽"
        viewModel.inputText = sent

        viewModel.send()

        #expect(await waitUntil { viewModel.messages.count == 3 && viewModel.messages.last?.status == .completed })
        // echo 응답이므로 보낸 문자열이 손실 없이 답변 안에 그대로 들어 있어야 한다
        #expect(viewModel.messages.last?.text.contains(sent) == true)
    }

    @Test func `an ai bubble stays pending until its first character arrives`() async throws {
        // 첫 글자까지의 공백(TTFT)이 있어야 대기 구간을 관측할 수 있다
        let service = MockChatService(delay: .milliseconds(300), chunkDelay: .zero, includesPrefix: { false })
        let viewModel = try ChatViewModel(
            service: service, store: makeIsolatedStore(), characterDelay: .zero,
            debounceInterval: .zero,
        )
        #expect(await waitUntil { viewModel.messages.first?.status == .completed })

        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil { viewModel.messages.last?.status == .pending })
        #expect(viewModel.messages.last?.sender == .ai)
        #expect(viewModel.messages.last?.text.isEmpty == true)

        // 첫 글자가 도착하면 대기가 끝난다
        #expect(await waitUntil { viewModel.messages.last?.status == .completed })
        #expect(viewModel.messages.last?.text.isEmpty == false)
    }

    @Test func `a response cancelled mid-stream settles instead of staying in streaming`() async throws {
        // 스트리밍 도중에 취소를 걸 수 있을 만큼 느리게 흘린다
        let service = MockChatService(delay: .zero, chunkDelay: .milliseconds(20), includesPrefix: { false })
        let viewModel = try ChatViewModel(
            service: service, store: makeIsolatedStore(), characterDelay: .milliseconds(5),
            debounceInterval: .zero,
        )
        #expect(await waitUntil { viewModel.messages.first?.status == .completed })

        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { viewModel.messages.contains { $0.status == .streaming } })

        // 두 번째 전송이 진행 중이던 응답 스트림을 취소한다
        viewModel.inputText = "B"
        viewModel.send()

        // 취소된 말풍선이 .streaming으로 방치되면 이 조건은 영영 참이 되지 않는다
        #expect(await waitUntil { viewModel.messages.allSatisfy { $0.status == .completed } })
    }

    @Test func `canSend recovers after a non-cancellation failure clears pendingTexts`() async throws {
        let viewModel = try ChatViewModel(
            service: FailingChatService(error: ChatServiceError.network),
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        viewModel.inputText = "B"
        viewModel.send()

        // 입력이 채워져 있는데도 막힌다면 이유는 대기 배치가 2개라는 것뿐이다
        viewModel.inputText = "C"
        #expect(!viewModel.canSend)

        // 실패가 pendingTexts를 비워야 다시 보낼 수 있게 된다
        #expect(await waitUntil { viewModel.canSend })
    }

    @Test func `canSend is false when inputText is empty`() throws {
        let viewModel = try ChatViewModel(store: makeIsolatedStore())
        viewModel.inputText = ""

        #expect(!viewModel.canSend)
    }

    @Test func `canSend is false when inputText is only whitespace`() throws {
        let viewModel = try ChatViewModel(store: makeIsolatedStore())
        viewModel.inputText = "  \n"

        #expect(!viewModel.canSend)
    }

    @Test func `canSend is true when inputText has non-whitespace characters`() throws {
        let viewModel = try ChatViewModel(store: makeIsolatedStore())
        viewModel.inputText = "안녕"

        #expect(viewModel.canSend)
    }

    @Test func `message is not expanded until expand is called`() throws {
        let viewModel = try ChatViewModel(store: makeIsolatedStore())
        let id = UUID()

        #expect(!viewModel.isExpanded(id))

        viewModel.expand(id)

        #expect(viewModel.isExpanded(id))
    }

    @Test func `expanding one message does not affect another`() throws {
        let viewModel = try ChatViewModel(store: makeIsolatedStore())
        let expandedId = UUID()
        let otherId = UUID()

        viewModel.expand(expandedId)

        #expect(viewModel.isExpanded(expandedId))
        #expect(!viewModel.isExpanded(otherId))
    }

    @Test func `saved history and expanded state are restored on next launch`() async throws {
        let store = try makeIsolatedStore()
        let first = try await makeSettledViewModel(store: store)
        first.inputText = "안녕하세요"
        first.send()
        _ = await waitUntil { first.messages.count == 3 && first.messages.last?.status == .completed }
        first.expand(first.messages[0].id)

        // 저장된 이력이 있으면 인사말을 다시 스트리밍하지 않고 완성된 텍스트를 그대로 복원한다
        let restored = ChatViewModel(store: store, characterDelay: .zero)

        #expect(restored.messages == first.messages)
        #expect(restored.isExpanded(first.messages[0].id))
    }

    @Test func `expanding a message persists it for the next launch`() async throws {
        let store = try makeIsolatedStore()
        let first = try await makeSettledViewModel(store: store)
        let id = first.messages[0].id

        first.expand(id)

        let restored = ChatViewModel(store: store, characterDelay: .zero)
        #expect(restored.isExpanded(id))
    }

    /// 재요청 원본 맵이 없는 고아 비종료만 대상 — 맵이 있으면 `.failed`로 닫힌다
    /// (`ChatViewModelInterruptedRestoreTests`).
    @Test func `orphan unfinished bubbles settle to completed without retry`() throws {
        let store = try makeIsolatedStore()
        // failedRequests 없음: 재시도 원본이 없어 버튼을 살릴 수 없다
        store.save(.init(
            messages: [
                Message(sender: .ai, text: "", status: .pending),
                Message(sender: .ai, text: "받다 만 텍스트", status: .streaming),
            ],
            expandedMessageIDs: [],
            failedRequests: nil,
        ))

        let restored = ChatViewModel(store: store, characterDelay: .zero)

        // 빈 고아는 폐기, 부분 텍스트 고아는 .completed
        #expect(restored.messages.count == 1)
        #expect(restored.messages[0].text == "받다 만 텍스트")
        #expect(restored.messages[0].status == .completed)
        #expect(!restored.canRetry(restored.messages[0].id))
    }

    @Test func `explicit messages override ignores saved history`() throws {
        let store = try makeIsolatedStore()
        store.save(.init(
            messages: [Message(sender: .ai, text: "저장된 이력", status: .completed)],
            expandedMessageIDs: [],
        ))
        let overrideMessages = [Message(sender: .user, text: "명시적 메시지", status: .completed)]

        let viewModel = ChatViewModel(messages: overrideMessages, store: store)

        #expect(viewModel.messages == overrideMessages)
    }
}
