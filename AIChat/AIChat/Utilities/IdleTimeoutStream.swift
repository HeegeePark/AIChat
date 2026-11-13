/// 청크 사이 간격을 감시해, 마지막 청크 뒤 `interval` 동안 새 청크가 없으면 스트림을 timeout으로 끊는다.
///
/// 전체 소요 시간이 아니라 **무응답 간격**이 기준이다 — 긴 답변이 정상 속도로 흘러나오는 동안에는
/// 총합이 얼마가 되든 끊기지 않아야 하고, 반대로 중간에 멈추면 그 자리에서 끊겨야 한다.
/// 감시는 스트림 시작 직후부터 걸리므로 첫 청크 지연(TTFT)도 같은 규칙으로 잡힌다.
nonisolated enum IdleTimeoutStream {
    static func make(
        from upstream: AsyncThrowingStream<String, Error>,
        interval: Duration,
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let consumer = Task {
                // 워치독을 소비 Task의 지역 변수로 둔다 — 마지막 도착 시각을 Task 간에 공유하면 락이 필요한데
                // Mutex는 iOS 18+라 타깃 위반이고, actor를 두면 청크마다 suspension이 하나 더 붙는다.
                var watchdog: Task<Void, Never>?
                defer { watchdog?.cancel() }

                func rearm() {
                    watchdog?.cancel()
                    watchdog = Task {
                        try? await Task.sleep(for: interval)
                        guard !Task.isCancelled else { return }
                        // 이미 종료된 continuation에 대한 finish는 no-op이라 소스의 정상 종료와 경합해도 안전하다.
                        continuation.finish(throwing: ChatServiceError.timeout)
                    }
                }

                rearm()
                do {
                    for try await chunk in upstream {
                        continuation.yield(chunk)
                        rearm()
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // 워치독 발화 → finish → onTermination → 소스 취소. 이 연결이 없으면 끊어도 프로듀서가 남는다.
            continuation.onTermination = { _ in consumer.cancel() }
        }
    }
}
