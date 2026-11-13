import SwiftUI
import UIKit

/// 접힌 말풍선 텍스트. 앞 `collapsedLines - 1`줄은 전체 폭을 그대로 쓰고, 마지막 줄만 "더 보기"가
/// 차지하고 남은 폭에서 말줄임된다 — 폭 배분을 HStack에 맡기므로 버튼과 원문이 겹칠 수 없다.
///
/// 측정·분할은 `MessageLineLimit` attributed API로 돌리고, 조각의 런 속성(font/color/strikethrough)을
/// `BubblePlainTextLabel(attributedText:)`에 그대로 넘긴다. "더 보기" Button·예약 폭·a11y id는 불변.
struct CollapsedBubbleText: View {
    /// 표시용 문자열 + 런 속성. plain 호출은 단일 font/color attributed로 만든다.
    private let attributedText: NSAttributedString
    /// "더 보기" 폰트 파생·예약 폭 base. 본문 base와 같아야 한다.
    let font: UIFont
    let width: CGFloat
    let lineSpacing: CGFloat
    /// "더 보기" 레이블 색상. 발신자별 대비는 이 뷰가 몰라도 되는 결정이라 호출자가 정해 넘긴다.
    let moreLabelColor: Color
    let moreLabelUnderline: Bool
    let onTapMore: () -> Void

    private static let moreLabel = MessageLineLimit.moreLabelText
    private static let labelSpacing = MessageLineLimit.moreLabelSpacing

    /// plain 경로. 사용자 완료 등 단일 font/color 본문.
    init(
        text: String,
        font: UIFont,
        textColor: UIColor,
        width: CGFloat,
        lineSpacing: CGFloat,
        moreLabelColor: Color,
        moreLabelUnderline: Bool,
        onTapMore: @escaping () -> Void,
    ) {
        attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ],
        )
        self.font = font
        self.width = width
        self.lineSpacing = lineSpacing
        self.moreLabelColor = moreLabelColor
        self.moreLabelUnderline = moreLabelUnderline
        self.onTapMore = onTapMore
    }

    /// attributed 경로. AI completed 마크다운 파싱 결과 등 런 속성을 보존한다.
    init(
        attributedText: NSAttributedString,
        font: UIFont,
        width: CGFloat,
        lineSpacing: CGFloat,
        moreLabelColor: Color,
        moreLabelUnderline: Bool,
        onTapMore: @escaping () -> Void,
    ) {
        self.attributedText = attributedText
        self.font = font
        self.width = width
        self.lineSpacing = lineSpacing
        self.moreLabelColor = moreLabelColor
        self.moreLabelUnderline = moreLabelUnderline
        self.onTapMore = onTapMore
    }

    var body: some View {
        let moreFont = MessageLineLimit.moreLabelFont(from: font)
        let reservedWidth =
            MessageLineLimit.textWidth(Self.moreLabel, font: moreFont) + Self.labelSpacing
        let parts = MessageLineLimit.collapsedSplit(attributedText: attributedText, width: width)
        let lastLine = MessageLineLimit.lastLineText(
            attributedText: parts.trailing, width: width, reservedWidth: reservedWidth,
        )

        VStack(alignment: .leading, spacing: lineSpacing) {
            BubblePlainTextLabel(
                attributedText: parts.leading,
                preferredMaxLayoutWidth: width,
                lineSpacing: lineSpacing,
                numberOfLines: MessageLineLimit.collapsedLines - 1,
            )

            HStack(alignment: .firstTextBaseline, spacing: Self.labelSpacing) {
                // 말줄임표는 lastLineText가 이미 붙였다. numberOfLines=1 + truncatingTail은 계산이 어긋나
                // 넘칠 때만 도는 안전망이라, 겹침은 이 경우에도 발생하지 않는다.
                BubblePlainTextLabel(
                    attributedText: lastLine,
                    preferredMaxLayoutWidth: max(1, width - reservedWidth),
                    lineSpacing: 0,
                    numberOfLines: 1,
                )

                // 폰트는 위 reservedWidth가 예약해 둔 자리와 반드시 같은 값이어야 한다 — 색상·밑줄만 더 얹는다.
                // layoutPriority: 없으면 HStack이 남는 폭을 두 쪽에 반씩 나눠 원문이 절반에서 잘린다.
                Button(action: onTapMore) {
                    Text(verbatim: Self.moreLabel)
                        .font(Font(moreFont))
                        .foregroundStyle(moreLabelColor)
                        .underline(moreLabelUnderline)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .layoutPriority(1)
                // VO/UITest 탐색용. 레이아웃·예약 폭·터치 영역은 건드리지 않는다.
                .accessibilityLabel(Self.moreLabel)
                .accessibilityIdentifier("moreButton")
            }
        }
    }
}
