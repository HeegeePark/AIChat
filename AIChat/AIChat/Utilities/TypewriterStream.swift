import os

/// 청크 스트림을 정확히 한 글자씩 흘려보내는 스트림으로 바꾼다.
///
/// "글자 단위로 보여준다"는 표현 계층의 관심사라 데이터 소스가 아니라 여기서 처리한다 —
/// 소스(mock이든 실서버든)는 임의 길이 청크만 뱉고, 이 변환이 글자로 쪼갠다.
///
/// 콜백+완료대기 객체가 아니라 스트림 변환인 이유: "다 흘러나왔다"가 `for await` 루프의 정상 종료와
/// 같은 말이 되어, 소스는 끝났지만 아직 덜 보여준 구간을 위한 별도 코디네이션이 필요 없다.
nonisolated enum TypewriterStream {
    /// 한 틱(지연 한 번)당 기본 속도 — 초당 50자.
    static let defaultCharacterDelay: Duration = .milliseconds(20)
    /// 밀린 글자를 이 횟수 안에 소진하도록 한 틱에 여러 글자를 내보낸다(기본 20ms 기준 약 1초 분량).
    static let catchUpTicks = 50

    /// 한 틱에 내보낼 글자 수. 지연을 줄이는 대신 틱당 글자 수를 늘려 따라잡는다 —
    /// 4ms 같은 짧은 `Task.sleep`은 오차가 지연 자체만큼 커서(실측: 4ms 목표가 ~10ms) 가속이 먹지 않는다.
    static func batchSize(forBacklog backlog: Int) -> Int {
        max(1, (backlog + catchUpTicks - 1) / catchUpTicks)
    }

    /// 소스를 지연 없이 빨아들여 글자 큐에 쌓는다 — 방출 속도에 맞춰 상류를 붙잡고 있으면 얼마나 밀렸는지 알 수 없다.
    private static func drainTask(
        from upstream: AsyncThrowingStream<String, Error>,
        into feed: AsyncThrowingStream<String, Error>.Continuation,
        backlog: OSAllocatedUnfairLock<Int>,
    ) -> Task<Void, Never> {
        Task {
            // 청크 경계가 grapheme cluster를 가를 수 있어(조합형 한글, ZWJ 이모지, 결합 악센트)
            // 마지막 한 글자는 다음 청크와 이어붙일 때까지 보류한다.
            // 상류가 중간에 throw해도 이미 받은 held는 흘려보낸다 — 부분 실패 말풍선이 마지막 글자를 잃으면 안 된다.
            var held = ""
            do {
                for try await chunk in upstream {
                    var buffer = held + chunk
                    guard !buffer.isEmpty else { continue }
                    held = String(buffer.removeLast())

                    for character in buffer {
                        backlog.withLock { $0 += 1 }
                        feed.yield(String(character))
                    }
                }

                if !held.isEmpty {
                    backlog.withLock { $0 += 1 }
                    feed.yield(held)
                    held = ""
                }
                feed.finish()
            } catch {
                if !held.isEmpty {
                    backlog.withLock { $0 += 1 }
                    feed.yield(held)
                    held = ""
                }
                feed.finish(throwing: error)
            }
        }
    }

    static func make(
        from upstream: AsyncThrowingStream<String, Error>,
        characterDelay: Duration = defaultCharacterDelay,
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            // 아직 안 보여준 글자 수. 소스를 붙잡아둔 채로는(소비 속도에 맞춰 next()를 부르는 구조)
            // 얼마나 밀렸는지 알 수가 없어서, 흡입과 방출을 두 Task로 갈라 이 카운터로 잇는다.
            // OSAllocatedUnfairLock: 두 Task가 공유하는 값이 Int 하나뿐이라 actor를 세울 이유가 없다.
            let backlog = OSAllocatedUnfairLock(initialState: 0)
            let (characters, feed) = AsyncThrowingStream<String, Error>.makeStream()

            let drain = drainTask(from: upstream, into: feed, backlog: backlog)

            let emit = Task {
                do {
                    var emittedSinceDelay = 0

                    for try await character in characters {
                        continuation.yield(character)
                        emittedSinceDelay += 1
                        let remaining = backlog.withLock { count -> Int in
                            count -= 1
                            return count
                        }

                        // 아직 이번 틱의 몫이 남았으면 지연 없이 다음 글자로 — 취소는 루프 꼭대기의 next()에서 관측된다
                        guard emittedSinceDelay >= batchSize(forBacklog: remaining) else { continue }
                        emittedSinceDelay = 0

                        // 취소를 여기서 throw로 흘려보내면 상류의 next()를 거치지 않고 빠져나가는데,
                        // AsyncStream은 소비 Task가 next()에서 취소를 관측할 때만 종료된다 —
                        // 그러면 상류 프로듀서가 안 멈추고 계속 돈다(측정으로 확인, gotchas 참고).
                        // 취소를 삼키고 루프 꼭대기(next())로 돌려보내 거기서 관측되게 한다.
                        try? await Task.sleep(for: characterDelay)
                        if Task.isCancelled {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // 소비 측이 취소되면 이 변환의 두 Task도 멈춰야 하고, 그래야 업스트림 이터레이터가 해제되며
            // 소스의 프로듀서까지 연쇄 취소된다. 이 연결이 없으면 취소해도 소스가 계속 돈다.
            continuation.onTermination = { _ in
                emit.cancel()
                drain.cancel()
            }
        }
    }
}
