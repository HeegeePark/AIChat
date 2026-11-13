import CoreText
import UIKit

/// Attributed 측정·접힘·말줄임 공개 API.
/// `MessageLineLimit` 본문 파일의 `file_length` / `type_body_length` 한도를 넘기지 않으려 분리한다.
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 아래 확장도 명시적으로 `nonisolated`를 붙인다.
nonisolated extension MessageLineLimit {
    // MARK: - 접힘 분할 (attributed)

    /// 접힘 분할을 **표시 문자열 인덱스** 기준으로 수행한다.
    ///
    /// - Returns: 원 attributed의 부분 문자열. 런(font·strikethrough 등)은 해당 범위에 보존된다.
    ///   `trailing` 앞쪽 공백·개행은 plain 경로와 같이 버린다(합쳐도 원문 전체와 길이 불일치 가능).
    static func collapsedSplit(
        attributedText: NSAttributedString, width: CGFloat,
    ) -> (leading: NSAttributedString, trailing: NSAttributedString) {
        let text = attributedText.string
        let lines = typesetLines(attributedText: attributedText, width: width)
        let leadingLines = collapsedLines - 1
        guard lines.count > leadingLines else {
            return (attributedText, NSAttributedString())
        }

        // CoreText가 잡은 줄 경계를 그대로 쓴다 — UILabel char wrapping과 같은 paragraph를 쓴다.
        let lastLeadingLine = CTLineGetStringRange(lines[leadingLines - 1])
        let splitUTF16 = lastLeadingLine.location + lastLeadingLine.length
        let leading = attributedSubstring(
            attributedText,
            utf16Range: NSRange(location: 0, length: splitUTF16),
        )

        // 마지막 줄이 공백·개행으로 시작하면 한 글자 밀려 보인다.
        let splitIndex = String.Index(utf16Offset: splitUTF16, in: text)
        let trimmedStart = text[splitIndex...].drop { $0.isWhitespace }.startIndex
        let trailingUTF16Start = text[..<trimmedStart].utf16.count
        let trailingLength = attributedText.length - trailingUTF16Start
        let trailing = attributedSubstring(
            attributedText,
            utf16Range: NSRange(location: trailingUTF16Start, length: trailingLength),
        )
        return (leading, trailing)
    }

    // MARK: - 접힘 인지 폭 (attributed)

    /// attributed 접힘 인지 폭. `minimumCollapsedWidth` 산출용 폰트는 표시 본문의 base(첫 런)다.
    static func collapsedAwareWidth(
        attributedText: NSAttributedString,
        hugWidth: CGFloat,
        maxWidth: CGFloat,
        minimumWidthFont: UIFont? = nil,
    ) -> CGFloat {
        let floorFont = minimumWidthFont ?? measurementBaseFont(of: attributedText)
        guard hugWidth > 0,
              lineCount(attributedText: attributedText, width: hugWidth) > collapsedLines
        else {
            return hugWidth
        }
        let floored = min(maxWidth, max(hugWidth, minimumCollapsedWidth(font: floorFont)))
        guard lineCount(attributedText: attributedText, width: floored) > collapsedLines else {
            return hugWidth
        }
        return floored
    }

    // MARK: - 마지막 줄 (attributed)

    /// 마지막 줄 attributed 조각. 원 런 속성은 보존하고, 말줄임 `…`만 **시스템 글꼴**로 붙인다.
    ///
    /// `…`에 본문(특히 한글) 런 글꼴을 물리면 CJK 가운데 점(⋯)으로 degener 한다.
    /// 전경색은 head 끝(또는 원문 첫 런)의 `foregroundColor`를 물린다 — 없으면 `UILabel` 기본
    /// `.label`로 떨어져 사용자 말풍선(흰 글자)에서 말줄임만 검게 보이는 회귀가 난다.
    /// 계약: 반환 문자열은 표시 plain의 접두 + `…`(넘칠 때)이며, `…` 직전 공백은 plain 경로와 같이 제거한다.
    static func lastLineText(
        attributedText: NSAttributedString, width: CGFloat, reservedWidth: CGFloat,
    ) -> NSAttributedString {
        let ellipsisFont = ellipsisSystemFont(for: attributedText)
        let available = width - reservedWidth - textWidth(ellipsis, font: ellipsisFont)
        guard available > 0 else {
            return NSAttributedString(
                string: ellipsis,
                attributes: ellipsisAttributes(font: ellipsisFont, colorSource: attributedText),
            )
        }

        let text = attributedText.string
        let lines = typesetLines(attributedText: attributedText, width: available)
        guard let firstLine = lines.first else { return attributedText }

        let range = CTLineGetStringRange(firstLine)
        let end = String.Index(utf16Offset: range.location + range.length, in: text)
        guard end < text.endIndex else { return attributedText }

        // 줄 끝에 딸려온 공백을 남기면 "… " 앞이 떠 보인다.
        var headEnd = end
        while headEnd > text.startIndex {
            let previous = text.index(before: headEnd)
            guard text[previous].isWhitespace else { break }
            headEnd = previous
        }
        let headUTF16 = text[..<headEnd].utf16.count
        let head = attributedSubstring(
            attributedText,
            utf16Range: NSRange(location: 0, length: headUTF16),
        )
        let result = NSMutableAttributedString(attributedString: head)
        result.append(
            NSAttributedString(
                string: ellipsis,
                attributes: ellipsisAttributes(font: ellipsisFont, colorSource: head),
            ),
        )
        return result
    }

    // MARK: - hug 폭 (attributed)

    /// attributed hug 폭. plain과 같이 앞 `widthProbeLength` **문자**만 조판한 근사다.
    static func fittedWidth(attributedText: NSAttributedString, maxWidth: CGFloat) -> CGFloat {
        let text = attributedText.string
        // `text.count`는 O(n)이라 쓰지 않는다 — 인덱스로 끊어 앞부분만 만진다.
        let probeEnd = text.index(
            text.startIndex, offsetBy: widthProbeLength, limitedBy: text.endIndex,
        ) ?? text.endIndex
        let probeUTF16 = text[..<probeEnd].utf16.count
        let probe = attributedSubstring(
            attributedText,
            utf16Range: NSRange(location: 0, length: probeUTF16),
        )
        return boundedWidth(of: probe, maxWidth: maxWidth)
    }

    /// 단축 없이 attributed 전체를 조판한 hug 폭.
    static func boundedWidth(of attributedText: NSAttributedString, maxWidth: CGFloat) -> CGFloat {
        let measured = preparingForMeasurement(attributedText)
        let bounds = measured.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        )
        // 반올림 오차로 마지막 글자가 잘리지 않게 1pt 여유
        return min(maxWidth, ceil(bounds.width) + 1)
    }

    // MARK: - 말줄임 토큰 속성

    /// 말줄임 토큰 전용 시스템 글꼴 — 한글 본문 런에 물리면 CJK 가운데 점이 된다.
    static func ellipsisSystemFont(for attributed: NSAttributedString) -> UIFont {
        UIFont.systemFont(ofSize: measurementBaseFont(of: attributed).pointSize)
    }

    /// `…` 속성: 시스템 글꼴 + 본문 전경색(있을 때). 글꼴은 본문 런을 물리지 않는다.
    static func ellipsisAttributes(
        font: UIFont,
        colorSource: NSAttributedString,
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let color = foregroundColor(nearEndOf: colorSource) {
            attributes[.foregroundColor] = color
        }
        return attributes
    }

    /// head 끝·원문 끝에서 앞으로 훑어 첫 `foregroundColor`를 쓴다. 없으면 nil.
    static func foregroundColor(nearEndOf attributed: NSAttributedString) -> UIColor? {
        guard attributed.length > 0 else { return nil }
        var index = attributed.length - 1
        while index >= 0 {
            var range = NSRange()
            if let color = attributed.attribute(
                .foregroundColor, at: index, effectiveRange: &range,
            ) as? UIColor {
                return color
            }
            index = range.location > 0 ? range.location - 1 : -1
        }
        return nil
    }
}
