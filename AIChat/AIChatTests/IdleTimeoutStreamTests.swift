@testable import AIChat
import Testing

struct IdleTimeoutStreamTests {
    struct DummyError: Error {}

    /// 워치독이 실제로 발화하기까지 기다리는 테스트들의 간격 — 짧게 잡아야 스위트가 느려지지 않는다.
    /// 이 값을 쓰는 테스트들은 소스가 `sleep` 없이 동기로 방출하므로 부하에 영향받지 않는다.
    static let interval: Duration = .milliseconds(100)

    /// 청크를 동기로 전부 방출하는 소스. `finishing: false`면 열린 채 멈춰 워치독을 발화시킨다.
    /// 버퍼가 무제한이라 소비 전에 yield해도 안전하고, `sleep`이 없어 전체 스위트 부하에 흔들리지 않는다.
    private func immediateUpstream(
        _ chunks: [String], finishing: Bool = true, failingWith error: Error? = nil,
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let error {
                continuation.finish(throwing: error)
            } else if finishing {
                continuation.finish()
            }
        }
    }

    /// 신호가 올 때까지 기다리되, 전파가 깨졌을 때 테스트가 영영 매달리지 않도록 상한을 둔다.
    private func received(_ signal: AsyncStream<Void>, within timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in signal {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// 기준이 전체 소요 시간이 아니라 무응답 간격임을 고정한다 — 5청크 × 250ms = 1.25s로 interval(1s)을 넘긴다.
    ///
    /// 이 테스트만 실제 `sleep` 페이싱이 필요해서, 간격 대비 여유를 **절대 시간으로** 크게 잡는다(250ms에 750ms 여유).
    /// 전체 `test_sim`은 UI 테스트가 병렬로 돌아 짧은 `sleep`이 수십 ms씩 밀리므로(gotchas 「테스트 실행 · 플레이크」)
    /// 20ms/100ms 같은 비율만 큰 조합은 실제로 깨졌다.
    @Test func `a steadily arriving source does not time out even past the interval`() async throws {
        let chunks = (1 ... 5).map(String.init)
        let paced = AsyncThrowingStream<String, Error> { continuation in
            let producer = Task {
                for chunk in chunks {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
        let stream = IdleTimeoutStream.make(from: paced, interval: .seconds(1))

        var collected: [String] = []
        for try await chunk in stream {
            collected.append(chunk)
        }

        #expect(collected == chunks)
    }

    @Test func `no first chunk within the interval times out`() async throws {
        // 아무것도 방출하지 않고 살아 있는 소스 — TTFT 지연이 곧 무응답 간격이다.
        let stream = IdleTimeoutStream.make(
            from: AsyncThrowingStream<String, Error> { _ in }, interval: Self.interval,
        )

        await #expect(throws: ChatServiceError.timeout) {
            for try await _ in stream {}
        }
    }

    @Test func `chunks emitted before the stall are delivered and then it times out`() async throws {
        let stream = IdleTimeoutStream.make(
            from: immediateUpstream(["가", "나"], finishing: false), interval: Self.interval,
        )

        var collected: [String] = []
        await #expect(throws: ChatServiceError.timeout) {
            for try await chunk in stream {
                collected.append(chunk)
            }
        }

        #expect(collected == ["가", "나"])
    }

    /// 소스가 정상 종료하면 워치독이 뒤늦게 발화해선 안 된다 — 종료 후 interval의 3배를 더 머물러도 에러가 없어야 한다.
    @Test func `a source that finishes normally does not time out afterwards`() async throws {
        let stream = IdleTimeoutStream.make(from: immediateUpstream(["가", "나"]), interval: Self.interval)

        let collected = try await Task { () -> [String] in
            var collected: [String] = []
            for try await chunk in stream {
                collected.append(chunk)
            }
            try await Task.sleep(for: Self.interval * 3)
            return collected
        }.value

        #expect(collected == ["가", "나"])
    }

    /// 취소가 상류까지 전파되지 않으면 응답을 끊어도 소스가 계속 돌아 누수가 된다.
    /// interval을 길게 잡아 워치독이 아니라 **취소**가 종료 원인임을 보장한다.
    @Test func `cancelling the consumer terminates the upstream`() async {
        let (signal, signalContinuation) = AsyncStream<Void>.makeStream()
        let upstream = AsyncThrowingStream<String, Error> { continuation in
            continuation.onTermination = { _ in signalContinuation.yield(()) }
            continuation.yield("안녕하세요")
        }

        let consumer = Task {
            for try await _ in IdleTimeoutStream.make(from: upstream, interval: .seconds(30)) {}
        }
        // 스트리밍이 시작된 뒤(중간에) 취소해야 의미 있는 경로를 탄다. 밀려도 interval이 30s라 판정은 안 흔들린다.
        try? await Task.sleep(for: .milliseconds(50))
        consumer.cancel()

        // 상한은 성공 시 비용이 0이라 느린 머신을 넉넉히 감안해 잡는다.
        #expect(await received(signal, within: .seconds(2)))
    }

    @Test func `a non timeout upstream error propagates unchanged`() async throws {
        let stream = IdleTimeoutStream.make(
            from: immediateUpstream(["가"], failingWith: DummyError()), interval: Self.interval,
        )

        await #expect(throws: DummyError.self) {
            for try await _ in stream {}
        }
    }
}
