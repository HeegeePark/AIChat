import SwiftUI
import UIKit

/// 말풍선 본문용 `UILabel` 래퍼. 글자 단위 줄바꿈(`.byCharWrapping`)으로 밀도 우선 개행을 연다.
///
/// ## 입력 계약 (plain / attributed 배타)
/// - **plain** (`init(text:font:textColor:…)`): 저장·표시 원문 `String` + 단일 font/color.
///   라벨이 font·color·paragraphStyle(`lineSpacing`, `lineBreakMode`)를 합성한다.
///   스트리밍·사용자·실패 경로가 이 이니셜라이저를 쓴다. 측정(`MessageLineLimit`)과 표시 문자열이 같다.
/// - **attributed** (`init(attributedText:…)`): 호출자가 런 속성(font/color/trait/strikethrough 등)과
///   base color를 이미 넣은 `NSAttributedString`을 넘긴다. **표시 문자열**(마커 제거본)이어야 한다.
///   라벨은 전체 범위에 `lineSpacing`과 `lineBreakMode`만 보정한다
///   (`numberOfLines == 1` → `.byTruncatingTail`, 그 외 → `.byCharWrapping`).
///   호출자가 미리 넣은 paragraph 속성(alignment 등)은 이 보정으로 덮인다 — 말풍선은 기본 정렬만 쓴다.
///
/// ## 접근성
/// - `accessibilityLabel` 기본값: plain은 `text`, attributed는 `attributedText.string`(표시 plain).
///   마크다운 마커 원문을 넣지 말 것. override는 `accessibilityLabelOverride`.
///
/// ## 성능
/// - `Applied` 입력이 같으면 `updateUIView`가 `attributedText`를 다시 넣지 않는다
///   (스트리밍 중 확정 블록 재조판 방지 — `StreamingBubbleText` 전제).
struct BubblePlainTextLabel: UIViewRepresentable {
    private let content: BubblePlainTextContent
    let preferredMaxLayoutWidth: CGFloat
    let lineSpacing: CGFloat
    var numberOfLines: Int = 0
    /// nil이면 표시 plain 문자열을 VoiceOver·XCUITest 라벨로 쓴다.
    var accessibilityLabelOverride: String?
    var accessibilityValueText: String?

    /// plain 경로. 스트리밍·사용자·실패 본문.
    init(
        text: String,
        font: UIFont,
        textColor: UIColor,
        preferredMaxLayoutWidth: CGFloat,
        lineSpacing: CGFloat,
        numberOfLines: Int = 0,
        accessibilityLabelOverride: String? = nil,
        accessibilityValueText: String? = nil,
    ) {
        content = .plain(text: text, font: font, textColor: textColor)
        self.preferredMaxLayoutWidth = preferredMaxLayoutWidth
        self.lineSpacing = lineSpacing
        self.numberOfLines = numberOfLines
        self.accessibilityLabelOverride = accessibilityLabelOverride
        self.accessibilityValueText = accessibilityValueText
    }

    /// attributed 경로. 호출자가 런 속성·base color를 합성해 넘긴다. 라벨은 lineSpacing·lineBreakMode만 보정.
    /// - Parameter attributedText: 표시용 문자열(마커 제거본) + 런 속성. a11y 기본 라벨은 `.string`.
    init(
        attributedText: NSAttributedString,
        preferredMaxLayoutWidth: CGFloat,
        lineSpacing: CGFloat,
        numberOfLines: Int = 0,
        accessibilityLabelOverride: String? = nil,
        accessibilityValueText: String? = nil,
    ) {
        content = .attributed(attributedText)
        self.preferredMaxLayoutWidth = preferredMaxLayoutWidth
        self.lineSpacing = lineSpacing
        self.numberOfLines = numberOfLines
        self.accessibilityLabelOverride = accessibilityLabelOverride
        self.accessibilityValueText = accessibilityValueText
    }

    private var displayPlain: String {
        switch content {
        case let .plain(text, _, _):
            text
        case let .attributed(attributed):
            attributed.string
        }
    }

    func makeUIView(context _: Context) -> IntrinsicHeightLabel {
        let label = IntrinsicHeightLabel()
        label.numberOfLines = numberOfLines
        label.lineBreakMode = .byCharWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.backgroundColor = .clear
        label.isAccessibilityElement = true
        return label
    }

    func updateUIView(_ label: IntrinsicHeightLabel, context _: Context) {
        let lineBreakMode: NSLineBreakMode = numberOfLines == 1 ? .byTruncatingTail : .byCharWrapping
        let applied = IntrinsicHeightLabel.Applied(
            content: content,
            preferredMaxLayoutWidth: preferredMaxLayoutWidth,
            lineSpacing: lineSpacing,
            numberOfLines: numberOfLines,
            accessibilityLabel: accessibilityLabelOverride ?? displayPlain,
            accessibilityValue: accessibilityValueText,
        )
        // SwiftUI는 값이 그대로여도 `updateUIView`를 부른다. 여기서 `attributedText`를 다시 대입하면
        // 내용이 같아도 전체 재조판·재드로우가 일어나므로(길이에 비례) 입력이 같으면 손대지 않는다.
        // 스트리밍 중 확정 블록이 다시 그려지지 않게 하는 것이 `StreamingBubbleText`의 전제다.
        guard label.applied != applied else { return }
        label.applied = applied

        label.numberOfLines = numberOfLines
        label.lineBreakMode = lineBreakMode
        label.preferredMaxLayoutWidth = preferredMaxLayoutWidth
        label.attributedText = Self.makeDisplayAttributedText(
            content: content,
            lineSpacing: lineSpacing,
            lineBreakMode: lineBreakMode,
        )
        // XCUITest `staticTexts[원문]`·VoiceOver가 attributedText만으로는 개행 포함 라벨을
        // 못 잡는 경우가 있어 accessibilityLabel을 명시한다.
        label.isAccessibilityElement = true
        label.accessibilityLabel = applied.accessibilityLabel
        label.accessibilityValue = applied.accessibilityValue
        label.invalidateIntrinsicContentSize()
    }

    /// plain 단일 font/color + 레이아웃 paragraph 합성. 기존 호출·테스트 호환용.
    static func makeAttributedText(
        text: String,
        font: UIFont,
        textColor: UIColor,
        lineSpacing: CGFloat,
        lineBreakMode: NSLineBreakMode,
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph,
            ],
        )
    }

    private static func makeDisplayAttributedText(
        content: BubblePlainTextContent,
        lineSpacing: CGFloat,
        lineBreakMode: NSLineBreakMode,
    ) -> NSAttributedString {
        switch content {
        case let .plain(text, font, textColor):
            makeAttributedText(
                text: text,
                font: font,
                textColor: textColor,
                lineSpacing: lineSpacing,
                lineBreakMode: lineBreakMode,
            )
        case let .attributed(input):
            applyingLayoutParagraph(
                to: input,
                lineSpacing: lineSpacing,
                lineBreakMode: lineBreakMode,
            )
        }
    }

    /// attributed 입력 전체에 lineSpacing·lineBreakMode만 덮어쓴다. 런 font/color 등은 유지.
    private static func applyingLayoutParagraph(
        to input: NSAttributedString,
        lineSpacing: CGFloat,
        lineBreakMode: NSLineBreakMode,
    ) -> NSAttributedString {
        guard input.length > 0 else { return input }
        let mutable = NSMutableAttributedString(attributedString: input)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        paragraph.lineSpacing = lineSpacing
        mutable.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: mutable.length),
        )
        return mutable
    }
}

/// plain / attributed 입력. `Applied` 동등 비교로 재조판 스킵에 쓴다.
private enum BubblePlainTextContent: Equatable {
    case plain(text: String, font: UIFont, textColor: UIColor)
    case attributed(NSAttributedString)

    static func == (lhs: BubblePlainTextContent, rhs: BubblePlainTextContent) -> Bool {
        switch (lhs, rhs) {
        case let (.plain(leftText, leftFont, leftColor), .plain(rightText, rightFont, rightColor)):
            leftText == rightText && leftFont == rightFont && leftColor == rightColor
        case let (.attributed(leftAttributed), .attributed(rightAttributed)):
            // 동일 인스턴스·동일 내용이면 true. 스트리밍 plain 경로의 String 비교와 같은 스킵 계약.
            leftAttributed.isEqual(to: rightAttributed)
        default:
            false
        }
    }
}

/// `preferredMaxLayoutWidth`에 맞춰 세로 intrinsic height를 내는 라벨.
final class IntrinsicHeightLabel: UILabel {
    /// 마지막으로 반영한 입력. 같은 값이 다시 오면 라벨을 건드리지 않기 위한 것이다.
    /// plain `text` 비교는 같은 String 인스턴스면 포인터 비교로 끝나 길이와 무관하다.
    /// attributed는 `NSAttributedString.isEqual(to:)`로 내용 동등을 본다.
    struct Applied: Equatable {
        fileprivate let content: BubblePlainTextContent
        let preferredMaxLayoutWidth: CGFloat
        let lineSpacing: CGFloat
        let numberOfLines: Int
        let accessibilityLabel: String
        let accessibilityValue: String?
    }

    var applied: Applied?

    /// `sizeThatFits`는 전체 텍스트를 조판해 길이에 비례한다(실측: 2500자에서 2.4ms).
    /// 한 번의 갱신마다 Auto Layout과 SwiftUI 사이징이 각각 물어봐 정확히 두 번 돌던 것을 한 번으로 줄인다.
    /// 입력(`attributedText`·`preferredMaxLayoutWidth`)이 바뀔 때만 버린다.
    private var cachedIntrinsicSize: CGSize?

    override var attributedText: NSAttributedString? {
        didSet { cachedIntrinsicSize = nil }
    }

    override var preferredMaxLayoutWidth: CGFloat {
        didSet {
            if abs(preferredMaxLayoutWidth - oldValue) > 0.5 {
                cachedIntrinsicSize = nil
                invalidateIntrinsicContentSize()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = preferredMaxLayoutWidth
        guard width > 0 else { return super.intrinsicContentSize }
        if let cachedIntrinsicSize {
            return cachedIntrinsicSize
        }

        let fitted = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let size = CGSize(width: min(ceil(fitted.width), width), height: ceil(fitted.height))
        cachedIntrinsicSize = size
        return size
    }
}
