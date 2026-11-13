/// 재요청 원본. 확정 실패뿐 아니라 in-flight 요청도 같은 맵에 실릴 수 있다.
/// 재시도는 사용자 메시지를 새로 쌓지 않고 이 값만으로 요청을 재현한다.
nonisolated enum FailedRequest: Codable, Sendable, Equatable {
    case greeting
    case batch([String])
}
