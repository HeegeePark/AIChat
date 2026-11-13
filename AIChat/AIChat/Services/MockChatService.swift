import Foundation
import SwiftUI

/// nonisolated + Sendable: 모든 프로퍼티가 불변값이라 액터 경계를 안전하게 넘나든다.
/// ChatViewModel.init 기본 파라미터 값(`MockChatService()`)으로 참조되는데, 기본 파라미터 값은 호출부 컨텍스트에서
/// 평가되어 액터 격리를 상속받지 않으므로 MainActor 격리 상태로는 그 자리에서 생성할 수 없다.
///
/// QA 키워드(`QA:…`)는 DEBUG 전용 확장 `MockChatService+QAKeywords.swift`에만 있다.
/// 제거: 그 파일 삭제 + 아래 `send`의 `#if DEBUG` 블록 한 줄 제거.
nonisolated struct MockChatService: ChatService, Sendable {
    let timeoutInterval: TimeInterval

    // ponytail: 캐주얼 프리픽스 문구는 여기 하나만 두면 되는 규모라 별도 타입 없이 static 배열로 관리
    // nonisolated 명시: 프로젝트 기본 액터 격리(MainActor)를 static 멤버가 물려받으면 이걸 읽는 send()까지
    // MainActor로 추론되어, nonisolated 컨텍스트(테스트 등)에서 호출할 때 Swift 6 격리 에러가 난다
    nonisolated static let prefixPhrases = [
        "좋은 질문이에요!", "네, 확인했어요!", "편하게 말씀해주세요.", "바로 답해드릴게요!",
    ]

    /// QA 확장·테스트가 같은 지연으로 스트림을 조립할 수 있게 internal로 둔다.
    let delay: Duration
    let chunkDelay: Duration
    let includesPrefix: @Sendable () -> Bool

    init(
        delay: Duration = .seconds(1.2),
        chunkDelay: Duration = .milliseconds(80),
        timeoutInterval: TimeInterval = 10,
        includesPrefix: @escaping @Sendable () -> Bool = { Bool.random() },
    ) {
        self.delay = delay
        self.chunkDelay = chunkDelay
        self.timeoutInterval = timeoutInterval
        self.includesPrefix = includesPrefix
    }

    func greeting() -> AsyncThrowingStream<String, Error> {
        stream(of: "안녕하세요! 무엇을 도와드릴까요?")
    }

    func send(_ texts: [String]) -> [AsyncThrowingStream<String, Error>] {
        #if DEBUG
            // QA 전용 — 키워드 없으면 nil. 제거 시 이 블록과 `MockChatService+QAKeywords.swift`만 지우면 된다.
            if let qaStreams = qaKeywordStreams(for: texts) {
                return qaStreams
            }
        #endif

        let answer = "'\(texts.joined(separator: "' 그리고 '"))'라고 하셨네요."
        guard includesPrefix() else { return [stream(of: answer)] }

        return [stream(of: Self.prefixPhrases.randomElement() ?? Self.prefixPhrases[0]), stream(of: answer)]
    }

    /// 실제 LLM 스트림처럼 임의 길이 청크로 흘린다. 첫 청크 앞의 `delay`는 서비스 요청 후 첫 청크 전 TTFT.
    /// QA 확장에서도 재사용한다.
    func stream(
        of text: String,
        delay: Duration? = nil,
        chunkDelay: Duration? = nil,
    ) -> AsyncThrowingStream<String, Error> {
        let initialDelay = delay ?? self.delay
        let betweenChunks = chunkDelay ?? self.chunkDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: initialDelay)

                    var rest = Substring(text)
                    while !rest.isEmpty {
                        // Substring.prefix는 Character 단위라 이 mock은 grapheme을 쪼개지 않는다.
                        // TypewriterStream이 경계 보호를 하는 건 실서버처럼 그러지 않는 소스를 위해서다.
                        let chunk = rest.prefix(Int.random(in: 2 ... 9))
                        rest = rest.dropFirst(chunk.count)
                        continuation.yield(String(chunk))
                        try await Task.sleep(for: betweenChunks)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// ponytail: 디버그 전용, 의도적으로 여기 둠 — MockChatService 동작을 Xcode 캔버스에서 바로 확인하기 위한 최소 프리뷰
private struct MockChatServicePreview: View {
    @State private var responseText = "응답 대기 중..."

    var body: some View {
        Text(responseText)
            .padding()
            .task {
                responseText = ""
                do {
                    for stream in MockChatService().send(["안녕하세요"]) {
                        for try await chunk in stream {
                            responseText += chunk
                        }
                        responseText += "\n"
                    }
                } catch {
                    responseText = "에러: \(error)"
                }
            }
    }
}

#Preview {
    MockChatServicePreview()
}
