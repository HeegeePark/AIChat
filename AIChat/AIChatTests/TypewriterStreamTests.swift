@testable import AIChat
import Testing

struct TypewriterStreamTests {
    struct DummyError: Error {}

    /// 청크를 그대로 방출하고 끝나는 업스트림. 버퍼가 무제한이라 동기 yield 후 finish해도 안전하다.
    private func makeUpstream(
        _ chunks: [String], failingWith error: Error? = nil,
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish(throwing: error)
        }
    }

    /// 지연 없이(.zero) 방출된 조각을 전부 모은다 — 테스트가 실제 타이핑 시간을 기다리지 않게 한다.
    private func pieces(from chunks: [String]) async throws -> [String] {
        var collected: [String] = []
        let stream = TypewriterStream.make(from: makeUpstream(chunks), characterDelay: .zero)
        for try await piece in stream {
            collected.append(piece)
        }
        return collected
    }

    /// 임의 길이로 쪼갠 청크 — 경계가 어디에 떨어지든 원문이 그대로 복원돼야 한다.
    private func chunked(_ text: String, by size: Int) -> [String] {
        stride(from: 0, to: text.count, by: size).map { offset in
            let start = text.index(text.startIndex, offsetBy: offset)
            let end = text.index(start, offsetBy: min(size, text.count - offset))
            return String(text[start ..< end])
        }
    }

    @Test func `urls newlines and tabs reassemble exactly`() async throws {
        let text = "참고: https://example.com/a/b?q=1&r=2#frag\n둘째 줄\t탭 뒤"

        let collected = try await pieces(from: chunked(text, by: 5))

        #expect(collected.joined() == text)
        #expect(collected.allSatisfy { $0.count == 1 })
    }

    @Test func `regional indicator flag split across chunks is emitted as one character`() async throws {
        // 🇰🇷 = 지역 지시자 두 개가 결합한 단일 Character
        let collected = try await pieces(from: ["\u{1F1F0}", "\u{1F1F7}"])

        #expect(collected == ["🇰🇷"])
    }

    @Test func `skin tone modifier split across chunks is emitted as one character`() async throws {
        let collected = try await pieces(from: ["👍", "\u{1F3FD}"])

        #expect(collected == ["👍🏽"])
    }

    @Test func `each emitted piece is exactly one character`() async throws {
        let collected = try await pieces(from: ["안녕", "하세요 hi!"])

        #expect(collected.allSatisfy { $0.count == 1 })
        #expect(collected.joined() == "안녕하세요 hi!")
    }

    @Test func `decomposed hangul split across chunks is emitted as one character`() async throws {
        // 초성 ᄀ + 중성 ᅡ = 가. 청크 경계가 이 사이를 가른다.
        let collected = try await pieces(from: ["\u{1100}", "\u{1161}"])

        #expect(collected == ["가"])
    }

    @Test func `zwj emoji family split across chunks is emitted as one character`() async throws {
        let family = "👨‍👩‍👧‍👦"
        let collected = try await pieces(from: ["👨\u{200D}", "👩\u{200D}👧\u{200D}", "👦"])

        #expect(collected == [family])
    }

    @Test func `combining accent split across chunks is emitted as one character`() async throws {
        let collected = try await pieces(from: ["caf", "e", "\u{301}"])

        #expect(collected.count == 4)
        #expect(collected.last == "é")
        #expect(collected.joined() == "café")
    }

    @Test func `empty stream finishes without emitting`() async throws {
        let collected = try await pieces(from: [])

        #expect(collected.isEmpty)
    }

    @Test func `empty chunks do not break the held character`() async throws {
        let collected = try await pieces(from: ["", "가", "", "나", ""])

        #expect(collected == ["가", "나"])
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

    /// 취소가 상류까지 전파되지 않으면 디바운스로 응답을 취소해도 소스가 계속 돌아 누수가 된다.
    /// 실제 취소 경로는 ChatViewModel의 `responseTask.cancel()`이므로 여기서도 소비 Task를 취소한다 —
    /// `break`로 루프를 빠져나오는 것만으로는 AsyncStream이 종료되지 않는다(측정으로 확인, gotchas 참고).
    @Test func `cancelling the consumer terminates the upstream`() async throws {
        let (signal, signalContinuation) = AsyncStream<Void>.makeStream()
        let upstream = AsyncThrowingStream<String, Error> { continuation in
            continuation.onTermination = { _ in signalContinuation.yield(()) }
            continuation.yield("안녕하세요 반갑습니다")
        }

        let consumer = Task {
            for try await _ in TypewriterStream.make(from: upstream, characterDelay: .milliseconds(5)) {}
        }
        // 몇 글자 흐른 뒤(스트리밍 도중) 취소해야 의미 있는 경로를 탄다
        try await Task.sleep(for: .milliseconds(20))
        consumer.cancel()

        // 실측 전파는 ~20ms. 상한은 성공 시 비용이 0이라 느린/부하 걸린 머신을 넉넉히 감안해 잡는다.
        #expect(await received(signal, within: .seconds(2)))
    }

    @Test func `batch size grows with the backlog and never drops below one character`() {
        // 여유로운 구간에서는 한 틱에 한 글자 — 가속만 하고 감속은 안 한다
        #expect(TypewriterStream.batchSize(forBacklog: 0) == 1)
        #expect(TypewriterStream.batchSize(forBacklog: 50) == 1)
        // 밀린 글자는 catchUpTicks(50) 틱 안에 소진하는 크기로 올린다
        #expect(TypewriterStream.batchSize(forBacklog: 51) == 2)
        #expect(TypewriterStream.batchSize(forBacklog: 300) == 6)
    }

    /// 소스가 순식간에 다 도착했는데도 고정 페이스로 흘리면 타이핑만 한참 남는다 — 그래서 밀린 만큼 가속한다.
    @Test func `a source that arrives all at once is typed out faster than the base pacing`() async throws {
        // 고정 20ms 한 글자씩이면 600자 = 12초. 틱당 여러 글자로 따라잡으면 실측 ~2.5초
        // (밀린 구간만 가속하고 마지막 catchUpTicks 분량은 다시 기본 속도로 흐르기 때문).
        let stream = TypewriterStream.make(
            from: makeUpstream([String(repeating: "가", count: 600)]), characterDelay: .milliseconds(20),
        )

        let elapsed = try await ContinuousClock().measure {
            for try await _ in stream {}
        }

        // 상한은 부하 걸린 머신을 감안해 넉넉히 — 가속이 빠지면 12초라 이 상한으로도 확실히 걸린다
        #expect(elapsed < .seconds(5))
    }

    /// throw 직전 held 문자를 버리지 않아야 부분 실패 말풍선이 마지막 글자를 잃는다.
    /// 이 yield를 지우면 아래 수집 결과가 깨지고, error 전파만 보면 통과한다.
    @Test func `held character is flushed before upstream error propagates`() async throws {
        let stream = TypewriterStream.make(
            from: makeUpstream(["안녕"], failingWith: DummyError()), characterDelay: .zero,
        )

        var collected: [String] = []
        do {
            for try await piece in stream {
                collected.append(piece)
            }
            Issue.record("expected DummyError to be thrown")
        } catch is DummyError {
            // expected
        }

        #expect(collected == ["안", "녕"])
    }
}
