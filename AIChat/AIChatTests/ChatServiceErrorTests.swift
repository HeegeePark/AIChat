@testable import AIChat
import Foundation
import Testing

struct ChatServiceErrorTests {
    @Test func `isRetryable matches policy table`() {
        #expect(ChatServiceError.timeout.isRetryable)
        #expect(ChatServiceError.network.isRetryable)
        #expect(ChatServiceError.unknown.isRetryable)
        #expect(!ChatServiceError.decoding.isRetryable)
        #expect(!ChatServiceError.unauthorized.isRetryable)
    }

    /// 유형별 사용자 문구 표 — raw Error 문자열이 아니라 고정 카피를 쓴다.
    @Test func `user facing copy matches policy table`() {
        #expect(MessageFailureCopy.emptyBubbleText(for: .timeout) == "응답을 받지 못했어요")
        #expect(MessageFailureCopy.emptyBubbleText(for: .network) == "네트워크 연결을 확인해 주세요")
        #expect(MessageFailureCopy.emptyBubbleText(for: .decoding) == "응답을 처리할 수 없어요")
        #expect(MessageFailureCopy.emptyBubbleText(for: .unauthorized) == "인증에 실패했어요")
        #expect(MessageFailureCopy.emptyBubbleText(for: .unknown) == "응답이 비어 있어요")

        #expect(MessageFailureCopy.partialFailureCaption(for: .timeout) == "요청 실패하였습니다.")
        #expect(MessageFailureCopy.partialFailureCaption(for: .network) == "네트워크 연결을 확인해 주세요")
        #expect(MessageFailureCopy.partialFailureCaption(for: .decoding) == "응답을 처리할 수 없어요")
        #expect(MessageFailureCopy.partialFailureCaption(for: .unauthorized) == "인증에 실패했어요")
        #expect(MessageFailureCopy.partialFailureCaption(for: .unknown) == "요청 실패하였습니다.")

        #expect(MessageFailureCopy.nonRetryableNotice == "다시 시도할 수 없는 오류예요")
    }

    @Test func `legacy failed message without failure is treated as retryable timeout`() {
        let message = Message(sender: .ai, text: "", status: .failed, failure: nil)

        #expect(MessageFailureCopy.resolvedFailure(for: message) == .timeout)
        #expect(MessageFailureCopy.isRetryable(for: message))
        #expect(MessageFailureCopy.emptyBubbleText(for: nil) == "응답을 받지 못했어요")
        #expect(MessageFailureCopy.partialFailureCaption(for: nil) == "요청 실패하였습니다.")
    }

    @Test func `resolvedFailure is nil when status is not failed`() {
        let message = Message(sender: .ai, text: "ok", status: .completed, failure: .network)
        #expect(MessageFailureCopy.resolvedFailure(for: message) == nil)
        #expect(!MessageFailureCopy.isRetryable(for: message))
    }
}
