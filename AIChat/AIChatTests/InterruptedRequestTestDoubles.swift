@testable import AIChat
import Foundation
import os

/// `send` 호출 배치 기록과 첫 응답 스트림 제어를 함께 제공하는 디바운스 테스트 더블.
/// 지연은 ViewModel에 주입하고, 스트림 진행은 테스트가 gate 메서드로 직접 연다.
nonisolated struct DebounceRecordingChatService: ChatService, Sendable {
    enum FirstResponse: Sendable {
        case immediate
        case controlled
    }

    private struct State: Sendable {
        var batches: [[String]] = []
        var firstSendInstant: ContinuousClock.Instant?
        var chunkContinuation: AsyncStream<String>.Continuation?
        var firstProducerStarted = false
        var firstProducerEnded = false
        var firstStreamCancelled = false
    }

    let timeoutInterval: TimeInterval = 10
    private let firstResponse: FirstResponse
    private let state: OSAllocatedUnfairLock<State>

    init(firstResponse: FirstResponse = .immediate) {
        self.firstResponse = firstResponse
        state = OSAllocatedUnfairLock(initialState: State())
    }

    var sendCallCount: Int {
        state.withLock { $0.batches.count }
    }

    var receivedBatches: [[String]] {
        state.withLock { $0.batches }
    }

    var firstSendInstant: ContinuousClock.Instant? {
        state.withLock { $0.firstSendInstant }
    }

    var isFirstProducerStarted: Bool {
        state.withLock { $0.firstProducerStarted }
    }

    var isFirstProducerEnded: Bool {
        state.withLock { $0.firstProducerEnded }
    }

    var wasFirstStreamCancelled: Bool {
        state.withLock { $0.firstStreamCancelled }
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_ texts: [String]) -> [AsyncThrowingStream<String, Error>] {
        let callIndex = state.withLock { state -> Int in
            state.batches.append(texts)
            if state.firstSendInstant == nil {
                state.firstSendInstant = .now
            }
            return state.batches.count - 1
        }
        guard callIndex == 0, firstResponse == .controlled else {
            return [immediateStream()]
        }
        return [controlledStream()]
    }

    func yieldFirst(_ chunk: String) {
        state.withLock { $0.chunkContinuation }?.yield(chunk)
    }

    private func immediateStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("done")
            continuation.finish()
        }
    }

    private func controlledStream() -> AsyncThrowingStream<String, Error> {
        let state = state
        return AsyncThrowingStream { responseContinuation in
            let chunks = AsyncStream<String> { chunkContinuation in
                state.withLock {
                    $0.chunkContinuation = chunkContinuation
                    $0.firstProducerStarted = true
                }
            }
            let producer = Task {
                defer {
                    state.withLock {
                        $0.chunkContinuation = nil
                        $0.firstProducerEnded = true
                    }
                }
                for await chunk in chunks {
                    guard !Task.isCancelled else { break }
                    responseContinuation.yield(chunk)
                }
                responseContinuation.finish()
            }
            responseContinuation.onTermination = { termination in
                if case .cancelled = termination {
                    state.withLock { $0.firstStreamCancelled = true }
                }
                state.withLock { $0.chunkContinuation }?.finish()
                producer.cancel()
            }
        }
    }
}

/// greeting/send 호출 횟수를 센다. 복원 경로가 자동 재전송하지 않는지 고정한다.
nonisolated struct CountingChatService: ChatService, Sendable {
    let timeoutInterval: TimeInterval = 10
    private let greetingCount: OSAllocatedUnfairLock<Int>
    private let sendCount: OSAllocatedUnfairLock<Int>

    init() {
        greetingCount = OSAllocatedUnfairLock(initialState: 0)
        sendCount = OSAllocatedUnfairLock(initialState: 0)
    }

    var greetingCallCount: Int {
        greetingCount.withLock { $0 }
    }

    var sendCallCount: Int {
        sendCount.withLock { $0 }
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        greetingCount.withLock { $0 += 1 }
        return AsyncThrowingStream { $0.finish() }
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        sendCount.withLock { $0 += 1 }
        return [AsyncThrowingStream { $0.finish() }]
    }
}

/// 응답을 영원히 흘리지 않는다 — send 직후 in-flight 스냅샷을 고정할 때 쓴다.
nonisolated struct HangingChatService: ChatService, Sendable {
    let timeoutInterval: TimeInterval = 60

    func greeting() -> AsyncThrowingStream<String, Error> {
        hang()
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        [hang()]
    }

    private func hang() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 지정 청크를 천천히 흘려 스트리밍 중 스냅샷을 잡는다.
nonisolated struct SlowChunkChatService: ChatService, Sendable {
    let timeoutInterval: TimeInterval = 60
    private let chunks: [String]
    private let chunkDelay: Duration

    init(chunks: [String], chunkDelay: Duration = .milliseconds(50)) {
        self.chunks = chunks
        self.chunkDelay = chunkDelay
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        let chunks = chunks
        let chunkDelay = chunkDelay
        return [
            AsyncThrowingStream { continuation in
                let task = Task {
                    for chunk in chunks {
                        try? await Task.sleep(for: chunkDelay)
                        if Task.isCancelled {
                            break
                        }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            },
        ]
    }
}

/// `send`만 hang하고 종료를 센다 — 재시도 deinit 취소 시 프로듀서 정지를 관측할 때 쓴다.
/// greeting은 즉시 finish (store 복원 경로에서는 호출되지 않지만 안전망).
nonisolated struct HangingSendWithTerminationCounter: ChatService, Sendable {
    let timeoutInterval: TimeInterval = 60
    private let activeCount: OSAllocatedUnfairLock<Int>
    private let terminatedCount: OSAllocatedUnfairLock<Int>

    init() {
        activeCount = OSAllocatedUnfairLock(initialState: 0)
        terminatedCount = OSAllocatedUnfairLock(initialState: 0)
    }

    var activeStreamCount: Int {
        activeCount.withLock { $0 }
    }

    var terminatedStreamCount: Int {
        terminatedCount.withLock { $0 }
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        let activeCount = activeCount
        let terminatedCount = terminatedCount
        return [
            AsyncThrowingStream { continuation in
                activeCount.withLock { $0 += 1 }
                let task = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    activeCount.withLock { $0 -= 1 }
                    terminatedCount.withLock { $0 += 1 }
                    task.cancel()
                }
            },
        ]
    }
}

/// 인사말은 hang(또는 일부 yield 후 hang), `send`는 즉시 성공 — 첫 전송 레이스 테스트용.
/// `HangingChatService`와 달리 send가 끝나야 응답 완료를 단언할 수 있다.
nonisolated struct HangingGreetingInstantSendService: ChatService, Sendable {
    let timeoutInterval: TimeInterval = 60
    /// greeting이 hang 전에 흘릴 청크. 비면 즉시 hang(빈 `.pending` 취소 경로).
    private let greetingPrefixChunks: [String]
    private let greetingPrefixDelay: Duration
    private let answer: String

    init(
        greetingPrefixChunks: [String] = [],
        greetingPrefixDelay: Duration = .milliseconds(10),
        answer: String = "echo-ok",
    ) {
        self.greetingPrefixChunks = greetingPrefixChunks
        self.greetingPrefixDelay = greetingPrefixDelay
        self.answer = answer
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        let chunks = greetingPrefixChunks
        let delay = greetingPrefixDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if Task.isCancelled {
                        break
                    }
                    continuation.yield(chunk)
                    try? await Task.sleep(for: delay)
                }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        let answer = answer
        return [
            AsyncThrowingStream { continuation in
                continuation.yield(answer)
                continuation.finish()
            },
        ]
    }
}
