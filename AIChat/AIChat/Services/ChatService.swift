import Foundation

protocol ChatService {
    /// 마지막 청크 뒤 이 시간 동안 새 청크가 없으면 무응답으로 본다(총 소요 시간이 아니라 간격 기준).
    var timeoutInterval: TimeInterval { get }

    /// 응답은 임의 길이 청크로 도착한다. 글자 단위 분할은 렌더 경로(`TypewriterStream`)의 몫이라
    /// 서비스는 "글자 단위로 보여준다"는 표현 계층의 사정을 몰라도 된다.
    func greeting() -> AsyncThrowingStream<String, Error>

    /// 배열 원소 하나가 말풍선 하나다. 호출부는 순서대로 하나씩 소비한다.
    /// 몇 개를 반환할지(캐주얼 프리픽스 포함 여부 등)는 구현체 재량이다.
    func send(_ texts: [String]) -> [AsyncThrowingStream<String, Error>]
}

/// 서비스 계층 실패 분류. associated value·underlying Error는 넣지 않는다 — 진단은 로그 전용.
/// `Message.failure`에 실려 영속화되므로 `Codable`이며, 액터 경계를 넘나들 수 있게 `nonisolated`.
nonisolated enum ChatServiceError: Error, Equatable, Sendable, Codable {
    case timeout
    case network
    case decoding
    case unauthorized
    case unknown

    /// 재시도 가능 여부. 클라이언트 재전송으로 회복될 수 있는 유형만 `true`.
    var isRetryable: Bool {
        switch self {
        case .timeout, .network, .unknown: true
        case .decoding, .unauthorized: false
        }
    }
}
