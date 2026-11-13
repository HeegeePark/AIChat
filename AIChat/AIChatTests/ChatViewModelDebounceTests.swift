@testable import AIChat
import Foundation
import Testing

@MainActor
struct ChatViewModelDebounceTests {
    private let quiet: Duration = .milliseconds(80)

    @Test func `send does not call service before debounce quiet completes`() async throws {
        let service = DebounceRecordingChatService()
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            messages: [],
            service: service,
            store: store,
            characterDelay: .zero,
            debounceInterval: quiet,
        )
        viewModel.inputText = "A"
        let startedAt = ContinuousClock.now

        viewModel.send()

        #expect(service.sendCallCount == 0)
        #expect(viewModel.messages.map(\.text) == ["A"])
        #expect(viewModel.messages.last?.sender == .user)
        #expect(viewModel.inputText.isEmpty)
        #expect(store.load()?.failedRequests?.values.contains(.batch(["A"])) == true)
        #expect(!viewModel.messages.contains { $0.sender == .ai })
        #expect(await waitUntil { service.sendCallCount == 1 })
        let firstSendAt = try #require(service.firstSendInstant)
        #expect(firstSendAt - startedAt >= quiet)
    }

    @Test func `second send restarts quiet interval and calls one combined batch`() async throws {
        let service = DebounceRecordingChatService()
        let resetQuiet: Duration = .milliseconds(200)
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: resetQuiet,
        )
        viewModel.inputText = "A"
        viewModel.send()
        try await Task.sleep(for: .milliseconds(50))
        viewModel.inputText = "B"
        let secondSendAt = ContinuousClock.now

        viewModel.send()

        #expect(service.sendCallCount == 0)
        #expect(viewModel.messages.filter { $0.sender == .user }.map(\.text) == ["A", "B"])
        #expect(await waitUntil { service.sendCallCount == 1 })
        #expect(service.receivedBatches == [["A", "B"]])
        let serviceCallAt = try #require(service.firstSendInstant)
        #expect(serviceCallAt - secondSendAt >= resetQuiet)
    }

    @Test func `third send is rejected while two texts are pending`() async throws {
        let service = DebounceRecordingChatService()
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: quiet,
        )
        viewModel.inputText = "A"
        viewModel.send()
        viewModel.inputText = "B"
        viewModel.send()
        viewModel.inputText = "C"

        #expect(!viewModel.canSend)
        viewModel.send()

        #expect(viewModel.inputText == "C")
        #expect(viewModel.messages.filter { $0.sender == .user }.map(\.text) == ["A", "B"])
        #expect(await waitUntil { service.sendCallCount == 1 })
        #expect(service.receivedBatches == [["A", "B"]])
    }

    @Test
    func `in-flight second send cancels the first stream and re-debounces before a combined request`() async throws {
        let service = DebounceRecordingChatService(firstResponse: .controlled)
        let viewModel = try ChatViewModel(
            messages: [],
            service: service,
            store: makeIsolatedStore(),
            characterDelay: .zero,
            debounceInterval: .milliseconds(20),
        )
        viewModel.inputText = "A"
        viewModel.send()
        #expect(await waitUntil {
            service.sendCallCount == 1 && service.isFirstProducerStarted
        })
        service.yieldFirst("partial")
        #expect(await waitUntil {
            viewModel.messages.contains { $0.sender == .ai && $0.status == .streaming }
        })
        viewModel.inputText = "B"

        viewModel.send()

        #expect(service.sendCallCount == 1)
        #expect(await waitUntil {
            service.wasFirstStreamCancelled && service.isFirstProducerEnded
        })
        #expect(await waitUntil { service.sendCallCount == 2 })
        #expect(service.receivedBatches == [["A"], ["A", "B"]])
        #expect(await waitUntil {
            viewModel.messages.last?.sender == .ai
                && viewModel.messages.last?.status == .completed
                && !viewModel.hasPendingSendBatch
        })
        #expect(viewModel.messages.allSatisfy { $0.status != .failed && $0.status != .streaming })
        viewModel.inputText = "C"
        #expect(viewModel.canSend)
    }
}
