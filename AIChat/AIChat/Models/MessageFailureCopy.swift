import Foundation

/// 실패 유형 → 사용자 문구 매핑. UI 표시와 말풍선 폭 측정이 같은 문자열을 쓰도록 한곳에서 고른다.
/// `Error.localizedDescription` / underlying 문자열은 쓰지 않는다.
nonisolated enum MessageFailureCopy {
    /// `.failed`이면서 `failure == nil`인 레거시 저장분은 retryable timeout으로 본다.
    static func resolvedFailure(for message: Message) -> ChatServiceError? {
        guard message.status == .failed else { return nil }
        return message.failure ?? .timeout
    }

    /// 레거시(`failure == nil`) 포함 재시도 가능 여부.
    static func isRetryable(for message: Message) -> Bool {
        resolvedFailure(for: message)?.isRetryable ?? false
    }

    /// 원문이 비어 있는 `.failed` 말풍선 본문(표시·`fittedTextWidth` 공용).
    static func emptyBubbleText(for failure: ChatServiceError?) -> String {
        switch failure ?? .timeout {
        case .timeout:
            "응답을 받지 못했어요"
        case .network:
            "네트워크 연결을 확인해 주세요"
        case .decoding:
            "응답을 처리할 수 없어요"
        case .unauthorized:
            "인증에 실패했어요"
        case .unknown:
            "응답이 비어 있어요"
        }
    }

    /// 부분 수신된 말풍선 아래 부가 안내.
    static func partialFailureCaption(for failure: ChatServiceError?) -> String {
        switch failure ?? .timeout {
        case .timeout:
            "요청 실패하였습니다."
        case .network:
            "네트워크 연결을 확인해 주세요"
        case .decoding:
            "응답을 처리할 수 없어요"
        case .unauthorized:
            "인증에 실패했어요"
        case .unknown:
            "요청 실패하였습니다."
        }
    }

    /// 재시도 불가 실패 행에 버튼을 대신하는 고정 문구.
    static let nonRetryableNotice = "다시 시도할 수 없는 오류예요"
}
