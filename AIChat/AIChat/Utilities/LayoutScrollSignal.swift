import Foundation

/// 전송 직후 대상 메시지 행이 mount·레이아웃된 시점을 `onAppear`로 받고, 스크롤 Task가 대기한다.
/// onAppear가 wait 등록보다 먼저 오면 `readyID`로, 반대면 continuation으로 맞춘다.
/// 폴백 sleep은 주 경로가 아니며, 신호가 안 올 때만 continuation을 풀어 준다.
@MainActor
final class LayoutScrollSignal {
    private var pendingID: UUID?
    private var readyID: UUID?
    private var continuation: CheckedContinuation<Void, Never>?
    private var fallbackTask: Task<Void, Never>?

    func begin(id: UUID) {
        cancelWait()
        pendingID = id
        readyID = nil
    }

    func signalAppear(id: UUID) {
        guard pendingID == id else { return }
        pendingID = nil
        readyID = id
        resumeWaiter()
    }

    /// - Parameter fallbackTimeout: 폴백 전용 상한. 주 경로는 `signalAppear`.
    func wait(for id: UUID, fallbackTimeout: Duration) async {
        if readyID == id {
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if readyID == id {
                cont.resume()
                return
            }
            continuation = cont
            fallbackTask?.cancel()
            fallbackTask = Task { @MainActor in
                // 폴백 전용 — 레이아웃 완료와 무관한 시간 상한.
                try? await Task.sleep(for: fallbackTimeout)
                guard !Task.isCancelled else { return }
                self.pendingID = nil
                self.resumeWaiter()
            }
        }
    }

    /// 연속 전송·Task 취소 시 대기 중인 continuation·폴백 Task를 정리한다.
    func cancelWait() {
        pendingID = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        resumeWaiter()
    }

    private func resumeWaiter() {
        fallbackTask?.cancel()
        fallbackTask = nil
        if let continuation {
            self.continuation = nil
            continuation.resume()
        }
    }
}
