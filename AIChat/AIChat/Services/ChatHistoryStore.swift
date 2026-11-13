import Foundation

/// UserDefaults 하나뿐인 구현체라 ChatService처럼 프로토콜로 추상화하지 않는다 —
/// 테스트 격리는 UserDefaults(suiteName:)로 이미 해결된다.
/// UserDefaults는 Sendable을 선언하지 않지만 내부적으로 스레드 안전하므로 @unchecked Sendable로 명시한다.
nonisolated struct ChatHistoryStore: @unchecked Sendable {
    struct PersistedState: Codable {
        var messages: [Message]
        var expandedMessageIDs: Set<UUID>
        /// 반드시 옵셔널로 둔다 — 합성 `init(from:)`은 프로퍼티에 기본값이 있어도 키가 없으면 던진다.
        /// 비옵셔널이면 이 키가 없는 예전 저장분이 통째로 디코딩에 실패해 대화 이력이 날아간다.
        var failedRequests: [UUID: FailedRequest]?
    }

    private static let key = "ChatHistoryStore.persistedState"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedState? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
