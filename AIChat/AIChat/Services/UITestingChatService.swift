import Foundation
import os

/// UI 테스트 전용: 첫 `send`만 즉시 timeout, 이후(재시도)는 고정 성공 텍스트.
/// 프로덕션 `MockChatService` 기본 지연·timeout 값은 건드리지 않는다.
nonisolated struct UITestingTimeoutOnceChatService: ChatService, Sendable {
    static let successText = "UITest-TimeoutRetry-OK"

    private let sendFailRemaining: OSAllocatedUnfairLock<Int>
    let timeoutInterval: TimeInterval = 10

    init(failCount: Int = 1) {
        sendFailRemaining = OSAllocatedUnfairLock(initialState: failCount)
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        // 인사 실패로 전송 플로우가 막히지 않게 즉시 짧은 성공.
        stream("안녕하세요")
    }

    func send(_: [String]) -> [AsyncThrowingStream<String, Error>] {
        let shouldFail = sendFailRemaining.withLock { count -> Bool in
            if count > 0 {
                count -= 1
                return true
            }
            return false
        }
        if shouldFail {
            return [AsyncThrowingStream { $0.finish(throwing: ChatServiceError.timeout) }]
        }
        return [stream(Self.successText)]
    }

    private func stream(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if !text.isEmpty {
                continuation.yield(text)
            }
            continuation.finish()
        }
    }
}
