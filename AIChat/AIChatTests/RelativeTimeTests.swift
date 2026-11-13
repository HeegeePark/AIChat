@testable import AIChat
import Foundation
import Testing

struct RelativeTimeTests {
    /// 고정 기준 시각. `.now`를 쓰면 테스트 실행 시각에 따라 결과가 흔들린다.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func string(secondsAgo: TimeInterval) -> String {
        RelativeTime.string(from: now.addingTimeInterval(-secondsAgo), to: now)
    }

    @Test func `just now covers the whole first minute`() {
        #expect(string(secondsAgo: 0) == "방금 전")
        #expect(string(secondsAgo: 30) == "방금 전")
        #expect(string(secondsAgo: 59) == "방금 전")
    }

    /// 갱신 주기(60초)가 정확히 이 경계에 맞춰져 있다 — 어긋나면 화면이 한 주기 늦게 바뀐다.
    @Test func `one minute is the first formatted value`() {
        #expect(string(secondsAgo: 60) == "1분 전")
    }

    /// 저장된 대화를 복원하거나 기기 시계가 보정되면 도착 시각이 미래일 수 있다.
    /// 포맷터에 그대로 넘기면 "1분 후" 같은 미래형이 나온다.
    @Test func `future timestamps fall back to just now`() {
        #expect(string(secondsAgo: -300) == "방금 전")
    }

    /// 로케일을 고정했으므로 기기 설정과 무관하게 같은 문자열이 나와야 한다.
    @Test func `formats larger units in korean`() {
        #expect(string(secondsAgo: 60 * 60) == "1시간 전")
        #expect(string(secondsAgo: 60 * 60 * 24) == "1일 전")
    }
}
