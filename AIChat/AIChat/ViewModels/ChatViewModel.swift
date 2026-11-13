import Foundation

@Observable
@MainActor
final class ChatViewModel {
    // ponytail: 배치 상한 2는 사용자와 합의된 값 — 응답 대기 중(pendingTexts) 3번째 전송을 막는 기준
    private static let maxPendingBatchSize = 2

    private(set) var messages: [Message]
    var inputText: String = ""
    private(set) var expandedMessageIDs: Set<UUID> = []

    private let service: ChatService
    private let store: ChatHistoryStore
    private let characterDelay: Duration
    private let debounceInterval: Duration
    private let debounceSleep: @Sendable (Duration) async throws -> Void
    private let deliverySettlementHook: @Sendable (DeliverySettlementPhase) async -> Void
    private var pendingTexts: [String] = []
    @ObservationIgnored
    private nonisolated(unsafe) var debounceTask: Task<Void, Never>?
    private var debounceGeneration: UUID?
    @ObservationIgnored
    private nonisolated(unsafe) var responseTask: Task<Void, Never>?
    private var responseGeneration: UUID?
    /// 인사말 전용 — `responseTask` 취소 축과 분리. 첫 `send`·deinit에서 취소한다.
    /// Observation 제외 + deinit cancel용. 생성·nil 정리는 MainActor 경로만 탄다.
    @ObservationIgnored
    private nonisolated(unsafe) var greetingTask: Task<Void, Never>?
    private var greetingGeneration: UUID?
    /// 재시도 전용 — responseTask·greetingTask 취소 축과 분리. 키 = retry 인자(실패 말풍선 ID).
    /// Observation 제외 + deinit cancel용. 생성·nil 정리는 MainActor 경로만 탄다.
    /// 재시도 핸들 맵. 생성·`defer` nil·`deinit` cancel은 이 파일의 `retry`만.
    @ObservationIgnored
    private nonisolated(unsafe) var retryTasks: [UUID: Task<Void, Never>] = [:]
    private var retryGenerations: [UUID: UUID] = [:]
    @ObservationIgnored
    var activeDeliveryRunIDs: Set<UUID> = []
    /// 모듈 내 재시도 전달 확장이 claim/rekey/clear 한다 (`private`면 확장 파일에서 못 씀).
    var requestOriginals = RequestOriginals()

    var groups: [MessageGroup] {
        MessageGroup.makeGroups(from: messages)
    }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pendingTexts.count < Self.maxPendingBatchSize
    }

    var canStop: Bool {
        greetingGeneration != nil
            || debounceGeneration != nil
            || responseGeneration != nil
            || !retryGenerations.isEmpty
    }

    init(
        messages: [Message]? = nil,
        service: ChatService = MockChatService(),
        store: ChatHistoryStore = ChatHistoryStore(),
        characterDelay: Duration = TypewriterStream.defaultCharacterDelay,
        debounceInterval: Duration = .milliseconds(300),
        debounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        deliverySettlementHook: @escaping @Sendable (DeliverySettlementPhase) async -> Void = { _ in },
    ) {
        self.service = service
        self.store = store
        self.characterDelay = characterDelay
        self.debounceInterval = debounceInterval
        self.debounceSleep = debounceSleep
        self.deliverySettlementHook = deliverySettlementHook

        if let messages {
            self.messages = messages
        } else if let saved = store.load() {
            // 진행 중 요청은 .failed로 닫고 네트워크를 다시 걸지 않는다.
            let restored = ChatHistoryRestore.restore(
                messages: saved.messages,
                failedRequests: saved.failedRequests ?? [:],
            )
            self.messages = restored.messages
            requestOriginals.map = restored.failedRequests
            expandedMessageIDs = saved.expandedMessageIDs
            // 디스크에도 정규화 결과를 남겨 다음 콜드 스타트가 같은 일을 반복하지 않게 한다.
            persist()
        } else {
            self.messages = []
            startGreeting()
        }
    }

    deinit {
        greetingTask?.cancel()
        debounceTask?.cancel()
        responseTask?.cancel()
        for task in retryTasks.values {
            task.cancel()
        }
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, pendingTexts.count < Self.maxPendingBatchSize else { return }

        // 진행 중 인사말만 끊는다 — responseTask 축과 섞지 않는다 (이미 끝났으면 no-op).
        greetingTask?.cancel()

        messages.append(Message(sender: .user, text: text, status: .completed))
        inputText = ""
        pendingTexts.append(text)
        // 네트워크·스트림 시작 전에 복구 원본을 남긴다(디바운스/취소 구간 포함).
        requestOriginals.recordBatch(pendingTexts)
        persist()

        scheduleResponse(for: pendingTexts)
    }

    /// 재시도 원본이 맵에 있을 때만 true. 유형 isRetryable과 축을 분리한다.
    func canRetry(_ id: UUID) -> Bool {
        requestOriginals.map[id] != nil
    }

    /// 실패한 말풍선을 지우고 그 요청만 다시 보낸다 — 사용자 메시지는 이미 화면에 있으므로 새로 쌓지 않는다.
    ///
    /// 진행 중인 응답(`responseTask`)·다른 실패의 재시도와 맵 키를 공유하지 않는다(run 지역 키).
    ///
    /// 스트림 대기는 `weak self`만 유지한다. `guard let self`로 `deliver` 전체를 붙잡으면
    /// `self → retryTasks → Task → self` 사이클이 생겨 deinit cancel이 무력해진다.
    func retry(_ id: UUID) {
        guard let request = requestOriginals.map.removeValue(forKey: id),
              let index = messages.firstIndex(where: { $0.id == id }) else { return }

        removeResponseRun(endingAt: index)
        // 스트림·timeout은 MainActor에서 미리 연다. Task 본문은 대기 구간에서 owner를 붙잡지 않는다.
        let streams: [AsyncThrowingStream<String, Error>] = switch request {
        case .greeting: [service.greeting()]
        case let .batch(batch): service.send(batch)
        }
        let timeout = service.timeoutInterval
        let characterDelay = characterDelay
        let settlementHook = deliverySettlementHook
        // Optional 파라미터로 owner를 넘기면 호출 시점에 강참조가 생겨 사이클이 복원된다 — weak 박스만 넘긴다.
        let ownerRef = WeakRef(self)
        let generation = UUID()
        let context = DeliveryContext(
            request: request,
            timeout: timeout,
            characterDelay: characterDelay,
            ownerRef: ownerRef,
            claimsPendingBatch: false,
            settlementHook: settlementHook,
        )
        retryGenerations[id] = generation
        retryTasks[id] = Task {
            defer {
                if let owner = ownerRef.value {
                    if owner.retryGenerations[id] == generation {
                        owner.retryTasks[id] = nil
                        owner.retryGenerations[id] = nil
                    }
                }
            }
            await Self.deliverDetached(streams, context: context)
        }
        persist()
    }

    /// 테스트 관측용 — `retryTasks`에 해당 실패 말풍선 ID 핸들이 있는지.
    func isRetryTaskTracked(_ id: UUID) -> Bool {
        retryTasks[id] != nil
    }

    /// 테스트 관측용 — 추적 중인 재시도 Task 개수.
    var retryTaskCountForTesting: Int {
        retryTasks.count
    }

    /// 같은 요청이 만든 앞선 말풍선(프리픽스 등)까지 함께 걷어낸다 — 재요청이 그것들을 다시 만들어 중복되기 때문이다.
    private func removeResponseRun(endingAt index: Int) {
        var start = index
        while start > 0, messages[start - 1].sender == .ai {
            start -= 1
        }
        requestOriginals.remove(ids: messages[start ... index].map(\.id))
        messages.removeSubrange(start ... index)
    }

    private func startGreeting() {
        let request = FailedRequest.greeting
        let streams = [service.greeting()]
        let timeout = service.timeoutInterval
        let characterDelay = characterDelay
        let settlementHook = deliverySettlementHook
        let ownerRef = WeakRef(self)
        let generation = UUID()
        let context = DeliveryContext(
            request: request,
            timeout: timeout,
            characterDelay: characterDelay,
            ownerRef: ownerRef,
            claimsPendingBatch: false,
            settlementHook: settlementHook,
        )
        greetingGeneration = generation
        greetingTask = Task {
            await Self.deliverDetached(streams, context: context)
            guard let owner = ownerRef.value,
                  owner.greetingGeneration == generation else { return }
            owner.greetingTask = nil
            owner.greetingGeneration = nil
            owner.persist()
        }
    }

    private func requestResponse(for batch: [String]) {
        let request = FailedRequest.batch(batch)
        let streams = service.send(batch)
        let timeout = service.timeoutInterval
        let characterDelay = characterDelay
        let settlementHook = deliverySettlementHook
        let ownerRef = WeakRef(self)
        let generation = UUID()
        let context = DeliveryContext(
            request: request,
            timeout: timeout,
            characterDelay: characterDelay,
            ownerRef: ownerRef,
            claimsPendingBatch: true,
            settlementHook: settlementHook,
        )
        responseGeneration = generation
        responseTask = Task {
            await Self.deliverDetached(streams, context: context)
            guard let owner = ownerRef.value,
                  owner.responseGeneration == generation else { return }
            owner.responseTask = nil
            owner.responseGeneration = nil
            // supersede 취소면 최신 send가 pending·앵커를 관리한다. 그 외 종료면 canSend 복구.
            if !Task.isCancelled {
                owner.pendingTexts = []
            }
            owner.persist()
        }
    }

    func applyConsumeOutcome(
        _ outcome: ConsumeOutcome,
        id: UUID,
        request: FailedRequest,
        runKey: inout UUID?,
    ) {
        switch outcome {
        case let .failed(error):
            if let index = messages.firstIndex(where: { $0.id == id }) {
                messages[index].failure = error
            }
            requestOriginals.recordFailure(error, id: id, request: request)
            // 실패 말풍선이 맵 키 — run 종료. 성공 clear와 이중 삭제 방지를 위해 runKey 비움은 deliver가 함.
            if !error.isRetryable {
                runKey = nil
            }
        case .cancelled:
            // 부분 텍스트는 .completed가 되지만, 맵은 고아 앵커로 옮겨 복원 시 재시도를 살린다.
            runKey = requestOriginals.recordCancellation(id: id, runKey: runKey)
        case .completed:
            break
        }
    }

    /// 재시도 전달 확장이 pending AI 말풍선을 붙일 때 사용 (`private(set) messages` 우회).
    func appendPendingAIMessage(id: UUID) {
        messages.append(Message(id: id, sender: .ai, text: "", status: .pending))
    }

    func append(_ text: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += text
        messages[index].status = .streaming
        persist()
    }

    func finish(_ id: UUID, outcome: ConsumeOutcome) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        switch outcome {
        case .failed:
            messages[index].status = .failed
        case .cancelled, .completed:
            if messages[index].text.isEmpty {
                messages.remove(at: index)
            } else {
                messages[index].status = .completed
            }
        }
    }

    func persist() {
        store.save(.init(
            messages: messages,
            expandedMessageIDs: expandedMessageIDs,
            failedRequests: requestOriginals.map,
        ))
    }
}

extension ChatViewModel {
    func stop() {
        guard canStop else { return }

        pendingTexts = []
        requestOriginals.clearPendingBatch()
        greetingTask?.cancel()
        debounceTask?.cancel()
        responseTask?.cancel()
        for task in retryTasks.values {
            task.cancel()
        }
        let stoppedRunIDs = activeDeliveryRunIDs
        activeDeliveryRunIDs.removeAll()
        requestOriginals.remove(ids: stoppedRunIDs)
        for id in stoppedRunIDs {
            finish(id, outcome: .cancelled)
        }
        persist()
    }

    func isExpanded(_ id: UUID) -> Bool {
        expandedMessageIDs.contains(id)
    }

    func expand(_ id: UUID) {
        expandedMessageIDs.insert(id)
        persist()
    }

    /// 마지막 메시지 기준 quiet 창을 다시 열고, 진행 중 응답은 기존 취소 정책으로 정착시킨다.
    private func scheduleResponse(for batch: [String]) {
        debounceTask?.cancel()
        responseTask?.cancel()

        let interval = debounceInterval
        let sleep = debounceSleep
        let generation = UUID()
        debounceGeneration = generation
        debounceTask = Task { [weak self] in
            defer {
                if let self, debounceGeneration == generation {
                    debounceTask = nil
                    debounceGeneration = nil
                }
            }
            do {
                try await sleep(interval)
            } catch {
                return
            }

            guard !Task.isCancelled, let self, debounceGeneration == generation else { return }
            requestResponse(for: batch)
        }
    }

    /// 응답 대기 중인 전송 배치가 열려 있는지. 뷰의 연속 전송 top 스크롤 앵커 해제에만 쓴다.
    var hasPendingSendBatch: Bool {
        !pendingTexts.isEmpty
    }
}
