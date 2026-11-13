@testable import AIChat
import Foundation
import os

/// ViewModel 테스트용 ChatService double.
/// 프로덕션 `MockChatService` 기본 경로에 실패를 심지 않고, N청크 후 throw / 즉시 throw / 빈 finish를 주입한다.
nonisolated struct FailingChatService: ChatService, Sendable {
    /// 스트림 하나(말풍선 하나)의 동작.
    enum StreamBehavior: Sendable {
        /// 청크 없이 즉시 실패.
        case fail(Error)
        /// 주어진 청크를 순서대로 yield한 뒤 실패.
        case chunksThenFail([String], Error)
        /// yield 없이 정상 finish (빈 성공 응답).
        case emptySuccess
        /// 텍스트를 한 청크로 흘린 뒤 정상 finish (재시도 성공 경로 등).
        case text(String)
    }

    let timeoutInterval: TimeInterval
    private let greetingBehavior: StreamBehavior
    private let sendBehaviors: [StreamBehavior]

    init(
        timeoutInterval: TimeInterval = 10,
        greeting: StreamBehavior = .fail(ChatServiceError.network),
        send: [StreamBehavior] = [.fail(ChatServiceError.network)],
    ) {
        self.timeoutInterval = timeoutInterval
        greetingBehavior = greeting
        sendBehaviors = send
    }

    /// 모든 스트림이 같은 에러로 즉시 실패 — 기존 단일-실패 스텁 호환.
    init(error: Error, timeoutInterval: TimeInterval = 10) {
        self.init(
            timeoutInterval: timeoutInterval,
            greeting: .fail(error),
            send: [.fail(error)],
        )
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        makeStream(greetingBehavior)
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        sendBehaviors.map(makeStream)
    }

    private func makeStream(_ behavior: StreamBehavior) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            switch behavior {
            case let .fail(error):
                continuation.finish(throwing: error)
            case let .chunksThenFail(chunks, error):
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish(throwing: error)
            case .emptySuccess:
                continuation.finish()
            case let .text(text):
                if !text.isEmpty {
                    continuation.yield(text)
                }
                continuation.finish()
            }
        }
    }
}

/// 첫 N번의 `send`만 실패하고 이후(재시도)는 성공. nonisolated + lock으로 액터 경계에서도 토글이 보인다.
nonisolated struct ToggleFailThenSucceedService: ChatService, Sendable {
    private let failRemaining: OSAllocatedUnfairLock<Int>
    let timeoutInterval: TimeInterval = 10

    init(failCount: Int = 1) {
        failRemaining = OSAllocatedUnfairLock(initialState: failCount)
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        stream("안녕하세요")
    }

    func send(_ texts: [String]) -> [AsyncThrowingStream<String, Error>] {
        let shouldFail = failRemaining.withLock { count -> Bool in
            if count > 0 {
                count -= 1
                return true
            }
            return false
        }
        if shouldFail {
            return [AsyncThrowingStream { $0.finish(throwing: ChatServiceError.network) }]
        }
        return [stream("'\(texts.joined())' 재시도 성공")]
    }

    private func stream(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(text)
            continuation.finish()
        }
    }
}
