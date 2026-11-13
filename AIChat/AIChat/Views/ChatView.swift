import SwiftUI

struct ChatView: View {
    // `private` 대신 module-internal(기본)로 둔 상태들은 `ChatView+Scroll.swift`의 extension이
    // 같이 쓴다 — Swift의 "같은 파일 내 private 접근" 규칙이 별도 파일 extension엔 적용되지
    // 않는다(`docs/gotchas.md` 참고, `ChatViewModel+RetryDelivery.swift`와 동일한 패턴).
    @State var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State var scrollTask: Task<Void, Never>?
    /// 취소된 이전 스크롤 Task의 `defer`가 새 `scrollTask` 핸들을 지우지 않게 세대 번호를 쓴다.
    @State var scrollTaskGeneration = 0
    @State private var isAtBottom = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// 전송 후 top 스크롤 전, 대상 행 레이아웃 신호를 중계한다(ViewModel 밖 뷰 로컬).
    @State var layoutScrollSignal = LayoutScrollSignal()
    /// 열린 전송 배치의 top 앵커(첫 유저 메시지). 이 값이 있는 동안만 하단 스페이서가 뷰포트
    /// 높이를 차지한다. **응답 완료(배치 close) 시점에는 더 이상 자동으로 nil을 대입하지
    /// 않는다** — 짧은 응답은 스페이서를 걷는 순간 콘텐츠가 뷰포트보다 작아져 `anchor: .top`이
    /// 물리적으로 불가능해지고, UIKit이 하단으로 clamp해 버린다(실측, QA 리포트 — 이전엔 배치
    /// close에 맞춰 지웠다가 이 문제가 재현됐다). 대신 사용자가 실제로 스크롤을 시작하거나
    /// (`ScrollViewBottomObserver.onDragBegin`) 다음 메시지를 보낼 때만 걷는다 — 그 시점엔
    /// 어차피 화면이 사용자 조작으로 움직이는 중이라 스페이서 소멸이 티가 안 난다.
    @State var postSendTopAnchorID: UUID?
    /// 같은 전송 배치에서 top 앵커를 이미 잡았는지 — `postSendTopAnchorID`와 분리한 이유는
    /// 위 주석 참고(배치가 닫혀도 스페이서용 앵커는 안 지우므로, "재앵커 방지" 가드는 별도 상태가 필요).
    @State var isSendBatchAnchored = false

    /// 기본값은 프로덕션 경로. UI 테스트는 bootstrap이 조립한 ViewModel을 주입한다.
    /// 기본 파라미터에 `ChatViewModel()`을 두지 않는다 — MainActor 격리가 기본 인자 평가에서 깨질 수 있다.
    init(viewModel: ChatViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? ChatViewModel())
    }

    /// 아바타는 `accessibilityHidden`인 순수 장식이라 Dynamic Type으로 키우지 않는다 —
    /// 커지면 그만큼 말풍선 폭을 잠식한다. 대신 이모지 크기를 이 값에서 파생시켜
    /// 이모지가 원을 벗어나는 일 자체를 없앤다.
    private let avatarSize: CGFloat = 28
    /// 아바타·말풍선·시간 캡션 사이 간격. `maxBubbleWidth` 계산과 행 `HStack`이 같은 값을 써야 한다.
    private static let rowSpacing: CGFloat = 8
    /// 말풍선 반대편 여백의 **하한**. 평소 여백은 `bubbleMaxWidthRatio`가 만들고,
    /// 이 값이 크면 시간 캡션이 그 여백을 나눠 쓰는 큰 글자 설정에서 한 줄 배치가 일찍 포기된다.
    private static let minOppositeGutter: CGFloat = 8
    /// VStack `.padding()` 좌우 합(기본 16pt × 2). 가용 폭 계산에 사용.
    private static let stackHorizontalPadding: CGFloat = 32
    /// 말풍선 텍스트 최대 폭 = 발신자별 가용 폭 × 이 비율. 비율은 공통, 가용 폭만 sender별.
    private static let bubbleMaxWidthRatio: CGFloat = 0.75
    /// 행 onAppear 신호가 안 올 때만 쓰는 폴백(주 경로 아님).
    static let layoutScrollFallback = Duration.milliseconds(150)
    /// 전송 후 상단 연출 전 UX 체류 — 레이아웃 대기가 아님.
    static let postSendScrollDwell = Duration.milliseconds(500)
    /// top 스크롤 이징 길이와 맞춤 — Task가 애니 중에 끝나 앵커 가드가 풀리지 않게 한다.
    static let postSendTopAnimation = Duration.milliseconds(350)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // ScrollView만 GeometryReader로 감싼다 — MessageInputView까지 포함해 감싸면
                    // 키보드가 올라올 때 입력창이 함께 밀려 올라가는 기본 키보드 회피 동작이 깨진다.
                    GeometryReader { geometry in
                        // 말풍선 상한은 발신자별: AI만 아바타 열을 예산에서 빼고, user는 contentWidth 기준
                        // (`BubbleWidthBudget`). AI 행은 아바타·캡션과 한 줄을 나눠 쓰므로 차감이 없으면
                        // 화면 밖으로 밀린다. user까지 같이 빼면 불필요하게 좁아진다.
                        let avatarColumn = avatarSize + Self.rowSpacing
                        // LazyVStack + UIScrollView offset 관찰(ScrollViewBottomObserver).
                        // Preference 마커는 Lazy가 화면 밖 마커를 언마운트해 갱신이 멈추므로 쓰지 않는다.
                        ScrollView {
                            // 스페이서를 Lazy+padding 밖에 두면 trailingSlack = 뷰포트 높이만으로
                            // “메시지 끝”과 content 끝이 맞는다 (spacing/padding 잔차 없음).
                            VStack(spacing: 0) {
                                LazyVStack(spacing: 12) {
                                    ForEach(viewModel.groups) { group in
                                        // 그룹은 sender가 하나 — 그룹 단위로 상한을 한 번 계산한다.
                                        let maxBubbleWidth = BubbleWidthBudget.maxBubbleWidth(
                                            for: group.sender,
                                            containerWidth: geometry.size.width,
                                            stackHorizontalPadding: Self.stackHorizontalPadding,
                                            avatarColumn: avatarColumn,
                                            ratio: Self.bubbleMaxWidthRatio,
                                        )
                                        groupView(group, maxBubbleWidth: maxBubbleWidth)
                                    }
                                }
                                .padding()

                                // 방금 보낸 메시지를 anchor: .top으로 스크롤하려면 그 뒤에 뷰포트 높이만큼 여백이
                                // 있어야 ScrollView가 바닥에서 clamp되지 않는다(짧은 메시지·응답 전이면 특히 그렇다).
                                // 배치가 열려 있을 때만 0이 아니다 — 상시 뷰포트 높이 스페이서를 두면
                                // 사용자가 자유 드래그로 그 빈 공간까지 스크롤해 화면이 텅 비어 보인다.
                                Color.clear
                                    .frame(height: postSendTopAnchorID != nil ? geometry.size.height : 0)
                            }
                            .background {
                                // trailingSlack = 목록 뒤 스페이서 높이(스페이서가 없을 땐 0). contentSize에는
                                // 들어가지만 “대화 최하단”은 메시지 끝 기준이어야 버튼이 떠 있지 않는다.
                                ScrollViewBottomObserver(
                                    isAtBottom: Binding(
                                        get: { isAtBottom },
                                        set: { newValue in
                                            guard newValue != isAtBottom else { return }
                                            // Reduce Motion On이면 버튼 등장/퇴장 슬라이드를 트리거하지 않고 즉시 반영.
                                            withMotionAnimation(.easeInOut(duration: 0.25)) {
                                                isAtBottom = newValue
                                            }
                                        },
                                    ),
                                    trailingSlack: postSendTopAnchorID != nil ? geometry.size.height : 0,
                                    onDragBegin: {
                                        // 사용자가 직접 스크롤을 시작하면 그 시점에만 스페이서를 걷는다 —
                                        // 손대기 전(자동)엔 절대 안 걷는다(위 postSendTopAnchorID 주석 참고).
                                        postSendTopAnchorID = nil
                                    },
                                )
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { isInputFocused = false }
                        .scrollDismissesKeyboard(.immediately)
                        .overlay(alignment: .bottomTrailing) {
                            if !isAtBottom {
                                ScrollToBottomButton(action: { scrollToBottom(proxy, animated: true) })
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 12)
                                    // Off: 하단 슬라이드+페이드. On: identity(즉시 토글).
                                    .transition(
                                        reduceMotion
                                            ? .identity
                                            : .move(edge: .bottom).combined(with: .opacity),
                                    )
                            }
                        }
                        .onAppear {
                            scrollToBottom(proxy, animated: false)
                        }
                    }

                    MessageInputView(
                        text: $viewModel.inputText,
                        canSend: viewModel.canSend,
                        canStop: viewModel.canStop,
                        isFocused: $isInputFocused,
                        onSend: {
                            viewModel.send()
                            guard let newMessageId = viewModel.messages.last?.id else {
                                isInputFocused = false
                                return
                            }
                            startPostSendScroll(proxy: proxy, messageId: newMessageId) {
                                isInputFocused = false
                            }
                        },
                        onStop: {
                            viewModel.stop()
                        },
                    )
                }
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            // 배치가 닫히면(응답 완료·실패 복구 등) 다음 전송이 새 top 앵커를 잡을 수 있게 "가드"만
            // 푼다 — 스페이서(postSendTopAnchorID)는 여기서 건드리지 않는다(위 주석 참고).
            .onChange(of: viewModel.hasPendingSendBatch) { _, isOpen in
                guard !isOpen else { return }
                isSendBatchAnchored = false
            }
        }
    }

    /// 실패 행: 부분 수신 부가 안내 + 재시도 버튼, 또는 재시도 불가 인지 문구.
    ///
    /// 부가 안내는 **부분 수신된 말풍선에만** 붙인다 — 받다 만 텍스트는 짧게 끝난 답변과 구분되지 않아
    /// 실패 신호가 따로 필요하지만, 한 글자도 못 받은 말풍선은 이미 유형별 빈 본문을 띄우고 있어
    /// 같은 말이 두 번 나온다. 재시도 불가일 때는 버튼 대신 `nonRetryableNotice`를 같은 자리에 둔다.
    private func retryRow(for message: Message) -> some View {
        MessageFailureRow(
            message: message,
            canRetry: viewModel.canRetry(message.id),
            leadingInset: avatarSize + Self.rowSpacing,
            onRetry: { viewModel.retry(message.id) },
        )
    }

    /// 시간 캡션이 말풍선과 한 줄에 들어가면 옆에, 아니면 아래에 붙인다.
    /// 글자 크기 임계값을 상수로 박지 않고 레이아웃이 실제 폭으로 판정하게 한다 — `retryRow`와 동일한 방식.
    ///
    /// 세로 배치를 `MessageBubble` 안이 아니라 여기서 하는 이유: 말풍선 아래에 캡션을 넣으면
    /// 행 `HStack`의 `.bottom` 정렬이 아바타를 캡션 높이까지 끌어내린다(재시도 버튼을 밖에 둔 것과 같은 이유).
    private func messageRow(
        _ item: GroupedMessage, sender: Message.Sender, maxBubbleWidth: CGFloat,
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            inlineRow(item, sender: sender, maxBubbleWidth: maxBubbleWidth)
            stackedRow(item, sender: sender, maxBubbleWidth: maxBubbleWidth)
        }
    }

    /// AI는 말풍선 오른쪽, 사용자는 왼쪽에 하단 정렬.
    private func inlineRow(
        _ item: GroupedMessage, sender: Message.Sender, maxBubbleWidth: CGFloat,
    ) -> some View {
        HStack(alignment: .bottom, spacing: Self.rowSpacing) {
            if sender == .user {
                Spacer(minLength: Self.minOppositeGutter)
                timestamp(for: item)
            }

            if sender == .ai {
                DecorativeChatAvatar(size: avatarSize, isVisible: item.isFirstInGroup)
            }

            bubble(for: item, maxBubbleWidth: maxBubbleWidth)

            if sender == .ai {
                timestamp(for: item)
                Spacer(minLength: Self.minOppositeGutter)
            }
        }
    }

    /// 큰 글자 설정에서 캡션이 한 줄에 못 들어갈 때의 대체 배치.
    /// AI 행 캡션은 아바타 칸만큼 들여써 말풍선 왼쪽 끝과 맞춘다 — `retryRow`와 동일한 규칙.
    private func stackedRow(
        _ item: GroupedMessage, sender: Message.Sender, maxBubbleWidth: CGFloat,
    ) -> some View {
        VStack(alignment: sender == .user ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: Self.rowSpacing) {
                if sender == .user {
                    Spacer(minLength: Self.minOppositeGutter)
                }

                if sender == .ai {
                    DecorativeChatAvatar(size: avatarSize, isVisible: item.isFirstInGroup)
                }

                bubble(for: item, maxBubbleWidth: maxBubbleWidth)

                if sender == .ai {
                    Spacer(minLength: Self.minOppositeGutter)
                }
            }

            timestamp(for: item)
                .padding(.leading, sender == .ai ? avatarSize + Self.rowSpacing : 0)
        }
    }

    private func bubble(for item: GroupedMessage, maxBubbleWidth: CGFloat) -> some View {
        MessageBubble(
            message: item.message,
            isLastInGroup: item.isLastInGroup,
            maxWidth: maxBubbleWidth,
            isExpanded: viewModel.isExpanded(item.message.id),
            onExpand: { viewModel.expand(item.message.id) },
        )
        // 스트리밍 중 글자마다 도는 부모 무효화에서 값이 안 바뀐 말풍선을 걸러낸다.
        // 계약과 근거는 `MessageBubble: Equatable` 주석 참고.
        .equatable()
    }

    /// 그룹핑 규칙(꼬리와 동일)에 맞춰 그룹의 마지막 말풍선에만 붙인다.
    @ViewBuilder
    private func timestamp(for item: GroupedMessage) -> some View {
        if item.isLastInGroup {
            MessageTimestamp(date: item.message.timestamp)
        }
    }

    private func groupView(_ group: MessageGroup, maxBubbleWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            ForEach(group.groupedMessages) { item in
                // 재시도 버튼은 말풍선이 아니라 행 아래에 붙인다 — 말풍선 안에 넣으면 행 HStack의
                // `.bottom` 정렬이 아바타를 버튼 높이까지 끌어내린다.
                //
                // 시간 캡션은 재시도 행보다 **위**에 온다(세로 배치일 때). 부분 수신 후 실패하면
                // 캡션·실패 문구·재시도 버튼이 한꺼번에 쌓이는데, 이 순서라야 캡션이 말풍선과 같은 줄에
                // 붙는 기본 크기와 읽는 순서가 같아진다 — 양쪽 다 "말풍선 → 시간 → 실패 → 재시도".
                VStack(alignment: .leading, spacing: 4) {
                    messageRow(item, sender: group.sender, maxBubbleWidth: maxBubbleWidth)

                    if item.message.status == .failed {
                        retryRow(for: item.message)
                    }
                }
                // ScrollViewReader 타깃 + 전송 후 레이아웃 신호(신규 mount). 기존 행 onAppear는
                // begin() 전이면 pending이 달라 no-op. LazyVStack에서도 새 행 mount 시 발화한다.
                .id(item.message.id)
                .onAppear {
                    layoutScrollSignal.signalAppear(id: item.message.id)
                }
            }
        }
    }
}

#Preview {
    ChatView()
}

/// AI 행 장식 아바타. `accessibilityHidden` 순수 장식 — Dynamic Type으로 키우지 않는다.
private struct DecorativeChatAvatar: View {
    let size: CGFloat
    let isVisible: Bool

    var body: some View {
        if isVisible {
            Circle()
                .fill(Color.cyan.opacity(0.25))
                .frame(width: size, height: size)
                .overlay {
                    Text("✨")
                        .font(.system(size: size * 0.5))
                }
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: size, height: size)
        }
    }
}
