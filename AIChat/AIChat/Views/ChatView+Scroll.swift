import SwiftUI

/// 스크롤 연출 헬퍼. `ChatView` struct body가 SwiftLint `type_body_length`(250줄)를 넘지 않게
/// 별도 extension으로 뺐다 — 상태는 여전히 `ChatView`의 `@State` 프로퍼티를 그대로 쓴다(`docs/gotchas.md` 참고).
extension ChatView {
    /// Reduce Motion Off일 때만 `withAnimation`으로 감싼다. On이면 본문만 즉시 실행.
    func withMotionAnimation(
        _ animation: Animation = .default,
        _ body: () -> Void,
    ) {
        if reduceMotion {
            body()
        } else {
            withAnimation(animation, body)
        }
    }

    func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastMessageId = viewModel.groups.last?.messages.last?.id else { return }
        // animated=false 또는 Reduce Motion On → 즉시 점프.
        if animated, !reduceMotion {
            withAnimation { proxy.scrollTo(lastMessageId, anchor: .bottom) }
        } else {
            proxy.scrollTo(lastMessageId, anchor: .bottom)
        }
    }

    /// 전송 직후 스크롤: 레이아웃 신호 → 키보드 dismiss → UX 체류 → top(상단).
    /// `anchor: .bottom` 강제 스크롤은 하지 않는다.
    /// 같은 전송 배치에서는 **첫 유저 메시지**만 top 앵커로 쓰고 재시작하지 않는다 — 가드는
    /// `postSendTopAnchorID`가 아니라 `isSendBatchAnchored`(배치 close 시 초기화)로 건다. 응답
    /// 완료 시 스페이서(`postSendTopAnchorID`)를 자동으로 지우지 않기로 했기 때문에(실측: 짧은
    /// 응답에서 스페이서가 사라지는 순간 `anchor: .top`이 불가능해져 하단으로 clamp됐다 — 아래
    /// `ScrollViewBottomObserver.onDragBegin` 주석·`ChatView`의 `postSendTopAnchorID` 주석 참고),
    /// 두 상태를 분리해야 "재앵커 방지"와 "스페이서 유지"를 독립적으로 제어할 수 있다.
    func startPostSendScroll(
        proxy: ScrollViewProxy,
        messageId: UUID,
        dismissKeyboard: @escaping () -> Void,
    ) {
        // 배치가 열려 있고 이미 첫 메시지 앵커가 있으면 두 번째 전송으로 top을 옮기지 않는다.
        if isSendBatchAnchored {
            return
        }
        isSendBatchAnchored = true

        let anchorID = messageId
        postSendTopAnchorID = anchorID

        // 이전 전송의 스크롤 시퀀스가 아직 살아있으면(예: 이전 짧은 배치가 끝나기 전 새로 전송)
        // 새 시퀀스와 겹치지 않게 취소한다. `begin`이 대기 중인 layout wait도 정리한다.
        scrollTask?.cancel()
        scrollTaskGeneration += 1
        let generation = scrollTaskGeneration

        layoutScrollSignal.begin(id: anchorID)
        scrollTask = Task { @MainActor in
            defer {
                // 취소된 세대의 defer가 후속 scrollTask 핸들을 nil로 덮어쓰지 않게 한다.
                if generation == scrollTaskGeneration {
                    scrollTask = nil
                }
            }

            await waitUntilLayoutReady(for: anchorID)
            guard !Task.isCancelled else {
                dismissKeyboard()
                return
            }

            // 키보드를 먼저 내려 뷰포트를 확보한 뒤, 잠깐 머물다 상단으로 올린다.
            dismissKeyboard()

            // 0.5초 체류는 Reduce Motion과 무관(연출 타이밍).
            try? await Task.sleep(for: Self.postSendScrollDwell)
            guard !Task.isCancelled else { return }

            // On이면 이징 없이 즉시 점프.
            withMotionAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(anchorID, anchor: .top)
            }

            // 애니 구간에도 Task를 살려 연타 레이스를 한 겹 줄인다.
            if !reduceMotion {
                try? await Task.sleep(for: Self.postSendTopAnimation)
            }
        }
    }

    /// 주 경로: 대상 행 `onAppear`. 폴백: 고정 상한 sleep(주 경로 아님).
    func waitUntilLayoutReady(for messageId: UUID) async {
        await layoutScrollSignal.wait(for: messageId, fallbackTimeout: Self.layoutScrollFallback)
    }
}
