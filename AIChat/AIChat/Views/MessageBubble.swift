import SwiftUI
import UIKit

/// 말풍선 한 줄(꼬리·최대 폭·접힘까지). 폭 측정과 표시가 같은 원문을 쓰도록 `message.layoutText` 하나만 본다.
/// AI·`.completed`만 인라인 마크다운을 1회 파싱해, 그 attributed를 측정·본문 렌더가 공유한다.
/// 실패 시 "다시 시도" 버튼은 여기 넣지 않는다 — 말풍선 안에 두면 아바타를 `.bottom` 정렬하는
/// `ChatView`의 행 `HStack`이 아바타를 버튼 높이까지 끌어내린다. 버튼은 행 단위 affordance라 `ChatView`가 소유한다.
struct MessageBubble: View {
    let message: Message
    let isLastInGroup: Bool
    /// 말풍선 텍스트 상한 폭. 행(`ChatView`)이 sender별로 계산해 넘긴다.
    /// 말풍선 내부에서 발신자별 비대칭 padding/frame으로 폭을 바꾸지 않는다(Spacer·ViewThatFits 회귀).
    let maxWidth: CGFloat
    let isExpanded: Bool
    let onExpand: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let horizontalPadding: CGFloat = 12
    private let lineSpacing: CGFloat = 2

    /// 말풍선 자체만 그린다 — 한쪽 끝 앵커링(`Spacer`)과 시간 캡션 배치는 `ChatView`가 소유한다.
    /// 여기서 `Spacer`를 품으면 폭이 항상 부모 제안만큼 늘어나, 행이 한 줄에 들어가는지 재는
    /// `ViewThatFits`가 언제나 "들어간다"고 판정해 캡션 넘침을 못 잡는다.
    var body: some View {
        // AI·completed 만 body당 1회 파싱. 폭 측정·접힘 판정·본문 렌더가 같은 값을 쓴다.
        let completedAIAttributed = Self.completedAIAttributedText(message: message, font: bodyFont)
        let width = fittedTextWidth(completedAIAttributed: completedAIAttributed)
        bubbleText(width: width, completedAIAttributed: completedAIAttributed)
            // 세로 이상적 높이로 확장해 부모 제안 높이에 잘리지 않게 한다.
            // 가로는 false — true면 제안 폭을 무시하고 한 줄로 뻗어 최대 폭 제한이 무력화된다.
            .fixedSize(horizontal: false, vertical: true)
            // maxWidth는 상한. 실측 폭을 고정해 HStack이 짧은 말풍선을 maxWidth까지 늘리지 못하게 한다.
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .background(message.sender == .user ? Color.accentColor : Color(.secondarySystemBackground))
            .clipShape(message.sender.bubbleShape(isLastInGroup: isLastInGroup))
            .modifier(InProgressAccessibility(
                isInProgress: message.status == .pending || message.status == .streaming,
            ))
    }

    @ViewBuilder
    private func bubbleText(
        width: CGFloat,
        completedAIAttributed: NSAttributedString?,
    ) -> some View {
        if message.status == .pending {
            TypingIndicator()
        } else if isCollapsed(width: width, completedAIAttributed: completedAIAttributed) {
            if let completedAIAttributed {
                CollapsedBubbleText(
                    attributedText: completedAIAttributed,
                    font: bodyFont,
                    width: width,
                    lineSpacing: lineSpacing,
                    moreLabelColor: message.sender.moreLabelColor,
                    moreLabelUnderline: message.sender.moreLabelUnderline,
                    onTapMore: onExpand,
                )
            } else {
                CollapsedBubbleText(
                    text: message.layoutText,
                    font: bodyFont,
                    textColor: message.sender.bodyTextColor,
                    width: width,
                    lineSpacing: lineSpacing,
                    moreLabelColor: message.sender.moreLabelColor,
                    moreLabelUnderline: message.sender.moreLabelUnderline,
                    onTapMore: onExpand,
                )
            }
        } else if message.status == .streaming {
            // 글자마다 갱신되는 유일한 말풍선이라 전체 재조판을 피하는 블록 렌더러를 쓴다.
            // 스트리밍 중 마크다운 파싱 없음 — plain layoutText만.
            StreamingBubbleText(
                text: message.layoutText,
                font: bodyFont,
                textColor: message.sender.bodyTextColor,
                width: width,
                lineSpacing: lineSpacing,
            )
        } else if let completedAIAttributed {
            BubblePlainTextLabel(
                attributedText: completedAIAttributed,
                preferredMaxLayoutWidth: width,
                lineSpacing: lineSpacing,
            )
        } else {
            // 빈 실패 본문: 시각 문구는 FailureCopy 유지, VO에 실패 맥락을 value로 붙여 완료 답변과 구분한다.
            // 부분 수신 실패·완료·사용자 plain은 원문 라벨만.
            let isEmptyFailure = message.status == .failed && message.text.isEmpty
            BubblePlainTextLabel(
                text: message.layoutText,
                font: bodyFont,
                textColor: message.sender.bodyTextColor,
                preferredMaxLayoutWidth: width,
                lineSpacing: lineSpacing,
                accessibilityValueText: isEmptyFailure ? "실패" : nil,
            )
        }
    }

    private var bodyFont: UIFont {
        .preferredFont(forTextStyle: .body)
    }

    /// AI + `.completed` 일 때만 파서 1회. 그 외는 nil → plain 경로.
    private static func completedAIAttributedText(
        message: Message,
        font: UIFont,
    ) -> NSAttributedString? {
        guard message.sender == .ai, message.status == .completed else { return nil }
        return MessageInlineMarkdown.attributedString(
            markdown: message.layoutText,
            font: font,
            color: message.sender.bodyTextColor,
        )
    }

    /// 카카오톡식 hug: `min(콘텐츠 폭, maxWidth)`. Dynamic Type 변경 시 재계산.
    /// 접힘 판정·분할·`UILabel` 줄바꿈이 모두 여기서 나온 **같은 폭**을 쓴다.
    ///
    /// 두 단계다: (1) 앞부분만 조판한 hug 폭(`fittedWidth` — 스트리밍 틱당 비용을 상수로 묶는다),
    /// (2) 접혀 그려질 말풍선에 한해 "더 보기" 버튼이 들어갈 최소 폭까지 넓히기(`collapsedAwareWidth`).
    private func fittedTextWidth(completedAIAttributed: NSAttributedString?) -> CGFloat {
        _ = dynamicTypeSize
        // 대기 중엔 텍스트가 없다 — 인디케이터가 말풍선 폭을 정한다
        if message.status == .pending {
            return TypingIndicator.width
        }
        if let attributed = completedAIAttributed {
            let hugWidth = MessageLineLimit.fittedWidth(
                attributedText: attributed, maxWidth: maxWidth,
            )
            // completedAIAttributed는 항상 completed — isExpanded만 보면 된다.
            guard !isExpanded else { return hugWidth }
            return MessageLineLimit.collapsedAwareWidth(
                attributedText: attributed,
                hugWidth: hugWidth,
                maxWidth: maxWidth,
                minimumWidthFont: bodyFont,
            )
        }

        let hugWidth = MessageLineLimit.fittedWidth(
            text: message.layoutText, font: bodyFont, maxWidth: maxWidth,
        )

        // 접혀 그려질 말풍선만 "더 보기" 버튼 자리를 보장한다 — 스트리밍·펼침 중엔 버튼이 없어
        // 넓힐 이유가 없다(한 글자짜리 줄이 반복되는 문장의 hug 폭이 버튼보다 좁아 세로로 쪼개지던 버그).
        // 이 경로는 전체 텍스트를 조판하지만 `completed`에서만 돌고, 값이 안 바뀐 말풍선은
        // 아래 `Equatable`이 걸러내므로 스트리밍 틱당 비용에는 들어가지 않는다.
        guard message.status == .completed, !isExpanded else { return hugWidth }
        return MessageLineLimit.collapsedAwareWidth(
            text: message.layoutText, font: bodyFont, hugWidth: hugWidth, maxWidth: maxWidth,
        )
    }

    private func isCollapsed(
        width: CGFloat,
        completedAIAttributed: NSAttributedString?,
    ) -> Bool {
        guard message.status == .completed, !isExpanded else { return false }
        if let attributed = completedAIAttributed {
            return MessageLineLimit.shouldCollapse(attributedText: attributed, width: width)
        }
        return MessageLineLimit.shouldCollapse(text: message.layoutText, font: bodyFont, width: width)
    }
}

/// `body`가 텍스트 길이에 비례하는 조판(`boundingRect` 2회 + `CTFramesetter` 1회)을 품고 있어,
/// 값이 안 바뀐 말풍선의 body 재평가를 반드시 막아야 한다. 기본 구조 비교는 `onExpand` 클로저에서
/// 항상 불일치가 난다 — 캡처가 동일해도 컨텍스트 박스가 매번 새로 할당되기 때문이다.
/// 그 결과 글자 하나마다 **화면의 모든 말풍선**이 전체 텍스트를 다시 조판했다
/// (실측: 2500자 스트리밍 중 20fps, `shouldCollapse` 2,300회/21.7초 → 붙인 뒤 59fps, 0회).
///
/// `onExpand`를 비교에서 빼도 안전한 이유: 그 클로저는 `viewModel.expand(message.id)`뿐이고
/// `viewModel`은 수명이 같은 참조, `message.id`는 아래 `message` 비교에 이미 포함된다.
/// 클로저가 `message`·`isExpanded` 밖의 상태에 의존하게 되면 이 계약이 깨지므로 함께 갱신할 것.
extension MessageBubble: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message
            && lhs.isLastInGroup == rhs.isLastInGroup
            && lhs.maxWidth == rhs.maxWidth
            && lhs.isExpanded == rhs.isExpanded
    }
}

/// 대기·스트리밍 중인 말풍선은 고정 레이블 하나로 노출한다.
/// 스트리밍 중 텍스트는 초당 수십 번 바뀌어서 VoiceOver 포커스가 있으면 매번 처음부터 다시 읽히고,
/// 대기 구간만 별도 요소로 노출하면 첫 글자가 도착하는 순간 그 요소가 사라져 포커스가 튄다.
/// 완료된 말풍선은 손대지 않는다 — "더 보기" 버튼이 별도 접근성 요소로 남아야 한다.
private struct InProgressAccessibility: ViewModifier {
    let isInProgress: Bool

    func body(content: Content) -> some View {
        if isInProgress {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("답변을 작성하고 있습니다")
        } else {
            content
        }
    }
}

private extension Message {
    /// 표시·측정이 같은 원문을 쓴다. 글자 단위 줄바꿈은 UILabel/CoreText 몫.
    ///
    /// 한 글자도 못 받고 실패한 말풍선은 원문이 비어 있다 — 그대로 재면 말풍선 폭이 0이 된다.
    /// 유형별 문구를 표시·`fittedTextWidth`가 공유한다(레거시 failure nil → timeout).
    var layoutText: String {
        if status == .failed, text.isEmpty {
            return MessageFailureCopy.emptyBubbleText(for: failure)
        }
        return text
    }
}

/// "더 보기" 버튼 대비: 사용자 말풍선은 파란 배경이라 흰색+밑줄, AI 말풍선은 밝은 배경이라 링크 색만으로 충분하다.
private extension Message.Sender {
    /// 사용자 말풍선은 파란 배경이라 흰 글자, AI 말풍선은 밝은 배경이라 기본 라벨 색이다.
    var bodyTextColor: UIColor {
        self == .user ? .white : .label
    }

    /// 모서리 하나만 뾰족한 말풍선 꼬리. 그룹의 마지막 말풍선에서 발신자 쪽 아래 모서리만 좁힌다.
    /// 커스텀 `Shape`+`Path` 대신 표준 `UnevenRoundedRectangle` — frame 크기를 안 바꿔 정렬이 안 흔들린다.
    func bubbleShape(isLastInGroup: Bool) -> UnevenRoundedRectangle {
        let cornerRadius: CGFloat = 16
        let tailCornerRadius: CGFloat = isLastInGroup ? 4 : cornerRadius

        return UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: self == .ai ? tailCornerRadius : cornerRadius,
            bottomTrailingRadius: self == .user ? tailCornerRadius : cornerRadius,
            topTrailingRadius: cornerRadius,
        )
    }

    var moreLabelColor: Color {
        self == .user ? .white : Color.accentColor
    }

    var moreLabelUnderline: Bool {
        self == .user
    }
}

#Preview("Long text") {
    GeometryReader { geometry in
        let maxWidth = (geometry.size.width - 32) * 0.75
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Message.longTextSamples) { message in
                    MessageBubble(
                        message: message, isLastInGroup: true, maxWidth: maxWidth,
                        isExpanded: false, onExpand: {},
                    )
                }
            }
            .padding()
        }
    }
}

// 인라인 마크다운 육안 확인. AI 3종 서식 + 접힘 장문 + 사용자 마커 리터럴.
#Preview("Inline Markdown") {
    GeometryReader { geometry in
        let maxWidth = (geometry.size.width - 32) * 0.75
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Message.inlineMarkdownSamples) { message in
                    MessageBubble(
                        message: message, isLastInGroup: true, maxWidth: maxWidth,
                        isExpanded: false, onExpand: {},
                    )
                }
            }
            .padding()
        }
    }
}
