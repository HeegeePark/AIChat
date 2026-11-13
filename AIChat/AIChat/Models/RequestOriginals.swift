import Foundation

/// 재요청 원본 맵. in-flight 키는 **deliver run마다 지역 변수**로 들고, 여기 슬롯은 send 앵커 전용이다.
/// (동시 retry가 공유 batchKey를 훔치지 않게 분리)
/// 순수 값 타입 — ViewModel이 소유·갱신하지만 액터에 묶이지 않는다.
nonisolated struct RequestOriginals: Sendable {
    /// 말풍선 id(또는 send/복구 앵커) → 재요청 원본.
    var map: [UUID: FailedRequest] = [:]
    /// `send()`가 붙잡아 둔 배치 앵커. 해당 배치의 `deliver`가 시작하면 claim 되어 nil이 된다.
    /// 인사말은 앵커 슬롯 없이 `rekey(from:nil)`로 말풍선 id에 바로 기록한다.
    var batchAnchor: UUID?

    /// 네트워크 전 배치 원본을 앵커에 기록. 같은 대기 배치면 앵커 유지·내용만 갱신.
    mutating func recordBatch(_ batch: [String]) {
        if let key = batchAnchor {
            map[key] = .batch(batch)
        } else {
            let key = UUID()
            batchAnchor = key
            map[key] = .batch(batch)
        }
    }

    /// 네트워크 전 대기 중인 배치만 닫는다. 같은 원본을 가진 과거 실패 엔트리는 유지한다.
    mutating func clearPendingBatch() {
        guard let key = batchAnchor else { return }
        batchAnchor = nil
        map.removeValue(forKey: key)
    }

    /// 이 deliver run이 이어받을 시작 키(있으면). claim 하면 슬롯을 비운다.
    /// `.greeting`은 항상 nil — 런타임이 앵커를 쓰지 않는다.
    mutating func claimRunKey(for request: FailedRequest) -> UUID? {
        guard case let .batch(batch) = request,
              let key = batchAnchor,
              map[key] == .batch(batch)
        else { return nil }
        batchAnchor = nil
        return key
    }

    /// run 키를 새 말풍선 id로 옮긴다. **다른 run의 키는 건드리지 않는다.**
    mutating func rekey(from oldKey: UUID?, to newID: UUID, request: FailedRequest) {
        if let oldKey {
            map.removeValue(forKey: oldKey)
        }
        map[newID] = request
    }

    mutating func recordFailure(_ error: ChatServiceError, id: UUID, request: FailedRequest) {
        if error.isRetryable {
            map[id] = request
        } else {
            map.removeValue(forKey: id)
        }
    }

    /// 취소된 말풍선 정리(디바운스 재전송 등). 실패로 기록하지 않는다.
    /// - 다른 run 키: 이 id 엔트리만 제거, 호출부 runKey는 유지
    /// - 이 run 키: 맵에서 제거하고 run 종료(nil). 새 `send`가 이미 써 둔 `batchAnchor`는 건드리지 않는다
    mutating func recordCancellation(id: UUID, runKey: UUID?) -> UUID? {
        map.removeValue(forKey: id)
        guard runKey == id else {
            return runKey
        }
        return nil
    }

    mutating func clearRunKey(_ key: UUID?) {
        guard let key else { return }
        map.removeValue(forKey: key)
    }

    /// 이 요청 원본과 같은 맵 엔트리를 모두 제거(성공 종료). run 키 추적과 이중으로 닫아 누수를 막는다.
    mutating func clearMatching(_ request: FailedRequest) {
        map = map.filter { $0.value != request }
    }

    mutating func remove(ids: some Sequence<UUID>) {
        for id in ids {
            map.removeValue(forKey: id)
        }
    }
}
