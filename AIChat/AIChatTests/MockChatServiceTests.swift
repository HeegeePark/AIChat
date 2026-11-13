@testable import AIChat
import Testing

/// `ChatService` 요구사항이 프로젝트 기본 격리(MainActor)를 물려받아 `send`/`greeting`도 MainActor 격리다 —
/// 호출부인 `ChatViewModel`이 `@MainActor`라 실사용에는 문제가 없고, 테스트도 같은 격리에서 호출한다.
@MainActor
struct MockChatServiceTests {
    /// 스트림이 흘린 청크를 전부 이어붙인다 — 청크 경계는 구현 디테일이라 결과 문자열로만 검증한다.
    private func text(of stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        return collected
    }

    @Test func `greeting streams a non-empty message`() async throws {
        let service = MockChatService(delay: .zero, chunkDelay: .zero)

        let greeting = try await text(of: service.greeting())

        #expect(!greeting.isEmpty)
    }

    @Test func `send without prefix returns a single stream`() async throws {
        let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })

        let streams = service.send(["안녕하세요"])

        #expect(streams.count == 1)
        #expect(try await text(of: streams[0]).contains("안녕하세요"))
    }

    @Test func `send echoes every text in the batch into one stream`() async throws {
        let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })

        let streams = service.send(["SwiftUI 텍스트 측정", "긴 텍스트도 계산되나요"])

        #expect(streams.count == 1)
        let answer = try await text(of: streams[0])
        #expect(answer.contains("SwiftUI 텍스트 측정"))
        #expect(answer.contains("긴 텍스트도 계산되나요"))
    }

    @Test func `send with prefix returns prefix stream followed by answer stream`() async throws {
        let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { true })

        let streams = service.send(["안녕하세요"])

        #expect(streams.count == 2)
        #expect(try await !text(of: streams[0]).isEmpty)
        #expect(try await text(of: streams[1]).contains("안녕하세요"))
    }

    /// 청크로 쪼개 흘려도 원문이 손실 없이 재구성되어야 한다.
    @Test func `chunks reassemble into the exact answer text`() async throws {
        let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })

        let answer = try await text(of: service.send(["가나다 abc 😀"])[0])

        #expect(answer == "'가나다 abc 😀'라고 하셨네요.")
    }

    @Test func `timeoutInterval is positive`() {
        let service = MockChatService()

        #expect(service.timeoutInterval > 0)
    }
}
