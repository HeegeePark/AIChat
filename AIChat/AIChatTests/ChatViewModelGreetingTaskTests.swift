@testable import AIChat
import Foundation
import Testing

/// 인사말 Task 추적·첫 전송 시 취소로 동시 스트리밍 레이스를 막는다.
@MainActor
struct ChatViewModelGreetingTaskTests {
    @Test func `first send while greeting hangs does not leave a failed greeting and finishes response`() async throws {
        let store = try makeIsolatedStore()
        let viewModel = ChatViewModel(
            service: HangingGreetingInstantSendService(),
            store: store,
            characterDelay: .zero,
        )

        // 인사 말풍선이 생기거나(빈 pending) 잠시 기다린 뒤 — settled 전에 전송.
        #expect(await waitUntil {
            viewModel.messages.contains { $0.sender == .ai }
        })

        viewModel.inputText = "첫 질문"
        viewModel.send()

        #expect(viewModel.messages.filter { $0.sender == .user }.map(\.text) == ["첫 질문"])

        #expect(await waitUntil(timeout: .seconds(4)) {
            let ais = viewModel.messages.filter { $0.sender == .ai }
            let users = viewModel.messages.filter { $0.sender == .user }
            let responseDone = ais.contains {
                $0.status == .completed && $0.text.contains("echo-ok")
            }
            let noFailedGreeting = !viewModel.messages.contains {
                $0.sender == .ai && $0.status == .failed
            }
            // hang 취소: 빈 인사는 제거, 부분만 남았다면 .completed
            let greetingSettled = !viewModel.messages.contains {
                $0.sender == .ai && ($0.status == .pending || $0.status == .streaming)
                    && !$0.text.contains("echo-ok")
            }
            return users.count == 1 && responseDone && noFailedGreeting && greetingSettled
        })

        for message in viewModel.messages where message.sender == .ai {
            #expect(message.failure == nil)
            #expect(message.status != .failed)
        }
    }

    @Test func `first send after partial greeting keeps partial text completed and not retryable`() async throws {
        let store = try makeIsolatedStore()
        // 청크 2개: TypewriterStream이 청크 마지막 1글자를 보류해도 첫 청크 앞글자가 화면에 남는다.
        let viewModel = ChatViewModel(
            service: HangingGreetingInstantSendService(
                greetingPrefixChunks: ["AB", "CD"],
                greetingPrefixDelay: .milliseconds(5),
            ),
            store: store,
            characterDelay: .zero,
        )

        #expect(await waitUntil {
            viewModel.messages.contains {
                $0.sender == .ai && !$0.text.isEmpty
            }
        })

        let greetingID = try #require(
            viewModel.messages.first(where: { $0.sender == .ai && !$0.text.isEmpty })?.id,
        )
        let partialBeforeSend = try #require(
            viewModel.messages.first(where: { $0.id == greetingID })?.text,
        )
        #expect(!partialBeforeSend.isEmpty)

        viewModel.inputText = "이어서"
        viewModel.send()

        #expect(await waitUntil(timeout: .seconds(4)) {
            guard let greeting = viewModel.messages.first(where: { $0.id == greetingID }) else {
                return false
            }
            let responseDone = viewModel.messages.contains {
                $0.sender == .ai && $0.status == .completed && $0.text.contains("echo-ok")
            }
            return greeting.status == .completed
                && !greeting.text.isEmpty
                && greeting.failure == nil
                && responseDone
        })

        let greeting = try #require(viewModel.messages.first(where: { $0.id == greetingID }))
        #expect(greeting.status == .completed)
        #expect(greeting.text.hasPrefix(partialBeforeSend) || greeting.text == partialBeforeSend)
        #expect(greeting.failure == nil)
        #expect(!viewModel.canRetry(greetingID))
    }
}
