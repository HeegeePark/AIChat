@testable import AIChat
import Foundation
import Testing

struct MessageTests {
    @Test func `encoding and decoding round-trips a message`() throws {
        let message = Message(sender: .ai, text: "안녕하세요", status: .completed)

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded == message)
        #expect(decoded.failure == nil)
    }

    @Test func `JSON without failure key decodes with failure nil`() throws {
        // failure 필드 도입 전 저장 형식 — 키가 없어도 이력이 날아가면 안 된다.
        // 손수 문자열 JSON은 enum 케이스 인코딩 형식에 취약하므로, 실제 인코딩 후 키만 제거한다.
        let original = Message(sender: .ai, text: "예전 이력", status: .completed)
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "failure")
        #expect(object["failure"] == nil)

        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Message.self, from: stripped)

        #expect(decoded.failure == nil)
        #expect(decoded.text == "예전 이력")
        #expect(decoded.status == .completed)
    }

    @Test func `failure round-trips through Codable`() throws {
        let message = Message(
            sender: .ai,
            text: "부분",
            status: .failed,
            failure: .network,
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded == message)
        #expect(decoded.failure == .network)
    }
}
