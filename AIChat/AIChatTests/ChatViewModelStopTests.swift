@testable import AIChat
import Foundation
import os
import Testing

// Stop의 네 Task 축·정착·owner 해제를 한 스위트에서 교차 검증한다.
// swiftlint:disable file_length
@MainActor
struct ChatViewModelStopTests {
    @Test func `stop before greeting text terminates producer and removes empty bubble`() async throws {
        let service = StopProbeService(greeting: .hang([]))
        let viewModel = try ChatViewModel(
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
        )

        #expect(await waitUntil { service.activeStreamCount == 1 && viewModel.canStop })
        viewModel.stop()

        #expect(await waitUntil {
            service.terminatedStreamCount == 1 && !viewModel.canStop
        })
        #expect(!viewModel.messages.contains { $0.sender == .ai })
        #expect(viewModel.messages.allSatisfy { $0.failure == nil })
        #expect(viewModel.requestOriginals.map.isEmpty)
    }

    @Test func `stop after partial greeting completes original without failure or retry`() async throws {
        let service = StopProbeService(greeting: .hang(["AB", "CD"]))
        let viewModel = try ChatViewModel(
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
        )
        #expect(await waitUntil {
            viewModel.messages.contains { $0.sender == .ai && !$0.text.isEmpty }
        })
        let id = try #require(viewModel.messages.first { $0.sender == .ai }?.id)

        viewModel.stop()

        #expect(await waitUntil {
            viewModel.messages.first { $0.id == id }?.status == .completed
                && !viewModel.canStop
        })
        let message = try #require(viewModel.messages.first { $0.id == id })
        #expect(!message.text.isEmpty)
        #expect(message.failure == nil)
        #expect(!viewModel.canRetry(id))
    }

    @Test func `stop during debounce keeps user and draft but closes pending batch`() async throws {
        let service = StopProbeService(send: [.finish("unused")])
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: service,
            store: store,
            characterDelay: .zero,
            debounceInterval: .seconds(30),
        )
        viewModel.inputText = "sent"
        viewModel.send()
        viewModel.inputText = "exact draft"
        #expect(viewModel.canStop)

        viewModel.stop()
        viewModel.stop()

        #expect(await waitUntil { !viewModel.canStop })
        #expect(service.sendCallCount == 0)
        #expect(viewModel.messages.map(\.text) == ["sent"])
        #expect(viewModel.inputText == "exact draft")
        #expect(!viewModel.hasPendingSendBatch)
        #expect(viewModel.canSend)
        let stoppedMap = store.load()?.failedRequests
        #expect(stoppedMap?.isEmpty == true)
    }

    @Test func `stop after debounce wait resumes still clears the active generation`() async throws {
        let gate = OneShotGate()
        let service = StopProbeService(send: [.finish("unused")])
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
            debounceSleep: { _ in await gate.wait() },
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { gate.isWaiting && viewModel.canStop })

        gate.open()
        viewModel.stop()

        #expect(await waitUntil { !viewModel.canStop })
        #expect(service.sendCallCount == 0)
        #expect(!viewModel.hasPendingSendBatch)
    }

    @Test func `stop during response TTFT terminates producer and removes empty bubble`() async throws {
        let service = StopProbeService(send: [.hang([])])
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: service,
            store: store,
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil {
            service.activeStreamCount == 1
                && viewModel.messages.contains { $0.sender == .ai && $0.status == .pending }
        })

        viewModel.stop()

        let stoppedState = try #require(store.load())
        #expect(stoppedState.failedRequests?.isEmpty == true)
        #expect(!stoppedState.messages.contains { $0.status == .pending || $0.status == .streaming })
        #expect(await waitUntil {
            service.terminatedStreamCount == 1 && !viewModel.canStop
        })
        #expect(viewModel.messages.filter { $0.sender == .user }.map(\.text) == ["A"])
        #expect(!viewModel.messages.contains { $0.sender == .ai })
        #expect(!viewModel.hasPendingSendBatch)
        #expect(viewModel.requestOriginals.map.isEmpty)
    }

    @Test func `stop during partial response completes text without failure or retry`() async throws {
        let service = StopProbeService(send: [.hang(["AB", "CD"])])
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil {
            viewModel.messages.contains { $0.sender == .ai && !$0.text.isEmpty }
        })
        let id = try #require(viewModel.messages.first { $0.sender == .ai }?.id)

        viewModel.stop()

        #expect(await waitUntil {
            viewModel.messages.first { $0.id == id }?.status == .completed
                && !viewModel.canStop
        })
        let message = try #require(viewModel.messages.first { $0.id == id })
        #expect(!message.text.isEmpty)
        #expect(message.failure == nil)
        #expect(!viewModel.canRetry(id))
        #expect(!viewModel.hasPendingSendBatch)
    }
}

extension ChatViewModelStopTests {
    @Test func `stop cancels all concurrent retries and preserves unrelated failed original`() async throws {
        let service = StopProbeService(send: [.hang([]), .hang([])])
        let store = try makeIsolatedStore()
        let failedA = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        let failedB = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .network)
        let failedOther = Message(id: UUID(), sender: .ai, text: "", status: .failed, failure: .timeout)
        store.save(.init(
            messages: [
                Message(sender: .user, text: "A", status: .completed), failedA,
                Message(sender: .user, text: "B", status: .completed), failedB,
                Message(sender: .user, text: "other", status: .completed), failedOther,
            ],
            expandedMessageIDs: [],
            failedRequests: [
                failedA.id: .batch(["A"]),
                failedB.id: .batch(["B"]),
                failedOther.id: .batch(["other"]),
            ],
        ))
        let viewModel = ChatViewModel(service: service, store: store, characterDelay: .zero)
        viewModel.retry(failedA.id)
        viewModel.retry(failedB.id)
        #expect(await waitUntil {
            service.activeStreamCount == 2 && viewModel.retryTaskCountForTesting == 2
        })

        viewModel.stop()

        #expect(await waitUntil {
            service.terminatedStreamCount == 2
                && viewModel.retryTaskCountForTesting == 0
                && !viewModel.canStop
        })
        #expect(!viewModel.canRetry(failedA.id))
        #expect(!viewModel.canRetry(failedB.id))
        #expect(viewModel.canRetry(failedOther.id))
        #expect(viewModel.requestOriginals.map[failedOther.id] == .batch(["other"]))
    }

    @Test func `stop then a new send completes normally`() async throws {
        let service = StopProbeService(send: [.hang([]), .finish("second-ok")])
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "first"
        viewModel.send()
        #expect(await waitUntil { service.activeStreamCount == 1 })
        viewModel.stop()
        #expect(await waitUntil { !viewModel.canStop })

        viewModel.inputText = "second"
        viewModel.send()

        #expect(await waitUntil {
            viewModel.messages.contains {
                $0.sender == .ai && $0.status == .completed && $0.text == "second-ok"
            }
                && !viewModel.canStop
        })
        #expect(service.sendCallCount == 2)
        #expect(!viewModel.hasPendingSendBatch)
        #expect(viewModel.requestOriginals.map.isEmpty)
    }

    @Test func `supersede keeps latest original and old cleanup cannot clear new canStop`() async throws {
        let service = StopProbeService(send: [.hang([]), .hang([])])
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: service,
            store: store,
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil {
            service.sendCallCount == 1 && service.activeStreamCount == 1
        })
        viewModel.inputText = "B"
        viewModel.send()

        #expect(await waitUntil {
            service.sendCallCount == 2
                && service.terminatedStreamCount == 1
                && service.activeStreamCount == 1
                && viewModel.canStop
        })
        let supersededMap = store.load()?.failedRequests
        #expect(supersededMap?.values.contains(.batch(["A", "B"])) == true)
        #expect(viewModel.hasPendingSendBatch)

        viewModel.stop()

        #expect(await waitUntil {
            service.terminatedStreamCount == 2 && !viewModel.canStop
        })
        #expect(!viewModel.hasPendingSendBatch)
        let stoppedMap = store.load()?.failedRequests
        #expect(stoppedMap?.isEmpty == true)
    }

    @Test func `supersede after stream read settles the old run as cancelled`() async throws {
        let settlementGate = OneShotGate()
        let service = StopProbeService(send: [.finish("first"), .hang([])])
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
            deliverySettlementHook: { phase in
                guard phase == .before else { return }
                await settlementGate.wait()
            },
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { settlementGate.isWaiting })

        settlementGate.open()
        viewModel.inputText = "B"
        viewModel.send()

        #expect(await waitUntil {
            service.sendCallCount == 2
                && service.activeStreamCount == 1
                && viewModel.requestOriginals.map.values.contains(.batch(["A", "B"]))
        })
        #expect(viewModel.requestOriginals.map.count == 1)
        #expect(!viewModel.requestOriginals.map.values.contains(.batch(["A"])))

        viewModel.stop()
        #expect(await waitUntil { !viewModel.canStop })
    }

    @Test func `supersede between response streams clears the completed prefix run`() async throws {
        let settlementGate = OneShotGate()
        let service = StopProbeService(sendGroups: [
            [.finish("prefix"), .hang([])],
            [.hang([])],
        ])
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
            deliverySettlementHook: { phase in
                guard phase == .after else { return }
                await settlementGate.wait()
            },
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { settlementGate.isWaiting })

        settlementGate.open()
        viewModel.inputText = "B"
        viewModel.send()

        #expect(await waitUntil {
            service.sendCallCount == 2
                && service.activeStreamCount == 1
                && viewModel.requestOriginals.map.values.contains(.batch(["A", "B"]))
        })
        #expect(viewModel.requestOriginals.map.count == 1)
        #expect(!viewModel.requestOriginals.map.values.contains(.batch(["A"])))

        viewModel.stop()
        #expect(await waitUntil { !viewModel.canStop })
    }

    @Test func `stop after failure settlement preserves the retryable original`() async throws {
        let settlementGate = OneShotGate()
        let service = StopProbeService(send: [.fail(.network)])
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
            deliverySettlementHook: { phase in
                guard phase == .after else { return }
                await settlementGate.wait()
            },
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil { settlementGate.isWaiting })
        let failedID = try #require(viewModel.messages.first { $0.status == .failed }?.id)
        #expect(viewModel.canRetry(failedID))

        settlementGate.open()
        viewModel.stop()

        #expect(await waitUntil { !viewModel.canStop })
        #expect(viewModel.canRetry(failedID))
        #expect(viewModel.requestOriginals.map[failedID] == .batch(["A"]))
    }

    @Test func `normal failure clears canStop while keeping retryable original`() async throws {
        let service = StopProbeService(send: [.fail(.network)])
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        viewModel.inputText = "A"
        viewModel.send()

        #expect(await waitUntil {
            viewModel.messages.contains { $0.status == .failed && $0.failure == .network }
                && !viewModel.canStop
        })
        let failed = try #require(viewModel.messages.first { $0.status == .failed })
        #expect(viewModel.canRetry(failed.id))
    }

    @Test func `idle stop is a no-op`() throws {
        let message = Message(sender: .user, text: "kept", status: .completed)
        let viewModel = try ChatViewModel(
            messages: [message],
            service: StopProbeService(),
            store: makeIsolatedStore(),
        )

        viewModel.stop()

        #expect(!viewModel.canStop)
        #expect(viewModel.messages == [message])
    }

    @Test func `deinit releases greeting debounce and response owners and terminates producers`() async throws {
        let greetingService = StopProbeService(greeting: .hang([]))
        var greeting: ChatViewModel? = try ChatViewModel(
            service: greetingService,
            store: makeIsolatedStore(),
            characterDelay: .zero,
        )
        let weakGreeting = try WeakRef(#require(greeting))
        #expect(await waitUntil { greetingService.activeStreamCount == 1 && greeting?.canStop == true })
        greeting = nil
        #expect(await waitUntil {
            weakGreeting.value == nil && greetingService.terminatedStreamCount == 1
        })

        var debounce: ChatViewModel? = try ChatViewModel(
            messages: [],
            service: StopProbeService(),
            store: makeIsolatedStore(),
            debounceInterval: .seconds(30),
        )
        let weakDebounce = try WeakRef(#require(debounce))
        debounce?.inputText = "A"
        debounce?.send()
        #expect(debounce?.canStop == true)
        debounce = nil
        #expect(await waitUntil { weakDebounce.value == nil })

        let responseService = StopProbeService(send: [.hang([])])
        var response: ChatViewModel? = try ChatViewModel(
            messages: [],
            service: responseService,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .zero,
        )
        let weakResponse = try WeakRef(#require(response))
        response?.inputText = "A"
        response?.send()
        #expect(await waitUntil {
            responseService.activeStreamCount == 1 && response?.canStop == true
        })
        response = nil
        #expect(await waitUntil {
            weakResponse.value == nil && responseService.terminatedStreamCount == 1
        })
    }
}

private final class OneShotGate: @unchecked Sendable {
    private struct State {
        var isOpen = false
        var isWaiting = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isWaiting: Bool {
        state.withLock { $0.isWaiting }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state in
                guard !state.isOpen else { return true }
                state.isWaiting = true
                state.continuation = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func open() {
        let continuation = state.withLock { state in
            state.isOpen = true
            state.isWaiting = false
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }
}

private nonisolated struct StopProbeService: ChatService, Sendable {
    enum Behavior: Sendable {
        case finish(String)
        case hang([String])
        case fail(ChatServiceError)
    }

    private struct State: Sendable {
        var sendCallCount = 0
        var activeStreamCount = 0
        var terminatedStreamCount = 0
    }

    let timeoutInterval: TimeInterval = 60
    private let greetingBehavior: Behavior
    private let sendGroups: [[Behavior]]
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(greeting: Behavior = .finish("hello"), send: [Behavior] = [.finish("done")]) {
        greetingBehavior = greeting
        sendGroups = send.map { [$0] }
    }

    init(greeting: Behavior = .finish("hello"), sendGroups: [[Behavior]]) {
        greetingBehavior = greeting
        self.sendGroups = sendGroups
    }

    var sendCallCount: Int {
        state.withLock { $0.sendCallCount }
    }

    var activeStreamCount: Int {
        state.withLock { $0.activeStreamCount }
    }

    var terminatedStreamCount: Int {
        state.withLock { $0.terminatedStreamCount }
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        makeStream(greetingBehavior)
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        let index = state.withLock { state -> Int in
            defer { state.sendCallCount += 1 }
            return state.sendCallCount
        }
        let behaviors = index < sendGroups.count ? sendGroups[index] : [.finish("done")]
        return behaviors.map(makeStream)
    }

    private func makeStream(_ behavior: Behavior) -> AsyncThrowingStream<String, Error> {
        switch behavior {
        case let .finish(text):
            AsyncThrowingStream { continuation in
                if !text.isEmpty {
                    continuation.yield(text)
                }
                continuation.finish()
            }
        case let .fail(error):
            AsyncThrowingStream { $0.finish(throwing: error) }
        case let .hang(prefixes):
            AsyncThrowingStream { continuation in
                state.withLock { $0.activeStreamCount += 1 }
                for prefix in prefixes {
                    continuation.yield(prefix)
                }
                let producer = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    state.withLock {
                        $0.activeStreamCount -= 1
                        $0.terminatedStreamCount += 1
                    }
                    producer.cancel()
                }
            }
        }
    }
}
