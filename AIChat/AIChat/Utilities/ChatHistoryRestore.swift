import Foundation

/// 저장된 대화 스냅샷을 복원 가능한 종료 상태로 정규화한다. 스트림을 이어받지 않는다.
nonisolated enum ChatHistoryRestore {
    /// 1. 맵에 원본이 있는 `.pending`/`.streaming` → `.failed` + `.unknown`(부분 텍스트 유지)
    /// 2. 맵 id에 말풍선이 없으면 빈 실패 앵커를 만들어 재시도 지점을 보장
    /// 3. 맵 없는 고아 비종료 → 텍스트 있으면 `.completed`, 빈 것은 폐기
    /// 4. `.completed`에 붙은 맵 잔재·메시지에 없는 맵 키는 제거
    nonisolated static func restore(
        messages: [Message],
        failedRequests: [UUID: FailedRequest],
    ) -> (messages: [Message], failedRequests: [UUID: FailedRequest]) {
        var map = failedRequests
        var restored: [Message] = []
        restored.reserveCapacity(messages.count + map.count)

        for message in messages {
            if map[message.id] != nil {
                switch message.status {
                case .pending, .streaming:
                    var failed = message
                    failed.status = .failed
                    failed.failure = .unknown
                    restored.append(failed)
                case .failed, .completed:
                    restored.append(message)
                }
            } else {
                switch message.status {
                case .failed, .completed:
                    restored.append(message)
                case .pending, .streaming:
                    guard !message.text.isEmpty else { continue }
                    var completed = message
                    completed.status = .completed
                    completed.failure = nil
                    restored.append(completed)
                }
            }
        }

        let existingIDs = Set(restored.map(\.id))
        for (id, _) in map where !existingIDs.contains(id) {
            restored.append(
                Message(id: id, sender: .ai, text: "", status: .failed, failure: .unknown),
            )
        }

        let finalIDs = Set(restored.map(\.id))
        let completedIDs = Set(restored.filter { $0.status == .completed }.map(\.id))
        map = map.filter { id, _ in
            finalIDs.contains(id) && !completedIDs.contains(id)
        }

        return (restored, map)
    }
}
