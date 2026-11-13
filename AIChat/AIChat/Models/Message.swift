import Foundation

nonisolated struct Message: Identifiable, Equatable, Sendable, Codable {
    enum Sender: Equatable, Codable {
        case user
        case ai
    }

    enum Status: Equatable, Codable {
        case pending
        case streaming
        case completed
        /// 무응답으로 끊긴 상태. 받은 텍스트가 없어도(가장 흔한 TTFT timeout) 말풍선이 남아야 재시도할 수 있다.
        case failed
    }

    let id: UUID
    let sender: Sender
    var text: String
    let timestamp: Date
    var status: Status
    /// 실패 분류. 키가 없는 옛 저장분은 `nil` — UI는 레거시 `.failed`를 retryable timeout으로 취급한다.
    var failure: ChatServiceError?

    init(
        id: UUID = UUID(),
        sender: Sender,
        text: String,
        timestamp: Date = Date(),
        status: Status,
        failure: ChatServiceError? = nil,
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.status = status
        self.failure = failure
    }
}
