@testable import AIChat
import Testing
import UIKit

/// attributed 측정 경로 계약. plain 스위트(`MessageLineLimitTests`)와 분리한 건
/// 그쪽이 `type_body_length` 상한에 닿아서다.
struct MessageLineLimitAttributedTests {
    private let font = UIFont.systemFont(ofSize: 17)
    private let boldFont = UIFont.systemFont(ofSize: 17, weight: .bold)
    private let wideWidth: CGFloat = 1000
    private let narrowWidth: CGFloat = 80

    private func plainAttributed(_ text: String, font: UIFont? = nil) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: MessageLineLimit.textAttributes(font: font ?? self.font),
        )
    }

    // MARK: - plain ↔ 단일 font attributed 동치

    @Test func `line count matches plain for single base font attributed`() {
        let samples = [
            "안녕하세요",
            Array(repeating: "line", count: MessageLineLimit.collapsedLines).joined(separator: "\n"),
            Array(repeating: "line", count: MessageLineLimit.collapsedLines + 1).joined(separator: "\n"),
            String(repeating: "가나다라마바사아자차", count: 20),
            Array(repeating: "word", count: 200).joined(separator: " "),
            String(repeating: "a", count: 80),
            "",
        ]

        for text in samples {
            for width in [narrowWidth, wideWidth, CGFloat(0)] {
                let plain = MessageLineLimit.lineCount(text: text, font: font, width: width)
                let attributed = MessageLineLimit.lineCount(
                    attributedText: plainAttributed(text), width: width,
                )
                #expect(plain == attributed, "text=\(text.prefix(20).debugDescription) width=\(width)")
            }
        }
    }

    @Test func `should collapse matches plain for single base font attributed`() {
        let short = "안녕하세요"
        let long = Array(repeating: "word", count: 200).joined(separator: " ")
        let exactlyCollapsedLines = Array(
            repeating: "line", count: MessageLineLimit.collapsedLines,
        ).joined(separator: "\n")
        let onePast = Array(
            repeating: "line", count: MessageLineLimit.collapsedLines + 1,
        ).joined(separator: "\n")

        for (text, width) in [
            (short, wideWidth),
            (long, narrowWidth),
            (exactlyCollapsedLines, wideWidth),
            (onePast, wideWidth),
            ("hello", CGFloat(0)),
            ("", wideWidth),
        ] {
            let plain = MessageLineLimit.shouldCollapse(text: text, font: font, width: width)
            let attributed = MessageLineLimit.shouldCollapse(
                attributedText: plainAttributed(text), width: width,
            )
            #expect(plain == attributed, "text=\(text.prefix(20).debugDescription) width=\(width)")
        }
    }

    // MARK: - 마커 plain ≠ 표시+bold 측정

    /// 마커를 포함한 원문을 plain으로 재면, 파싱 후 표시 문자열(+ bold 런)과 줄 수가 달라질 수 있다.
    /// 이 샘플은 그 차이를 고정해, 측정을 마커 원문에 두면 접힘이 어긋난다는 계약을 잠근다.
    @Test func `marker laden plain line count can differ from bold display measurement`() {
        // 단위마다 마커 4글자 vs 표시 1글자 — 같은 반복 횟수면 plain 원문이 훨씬 길다.
        let unitCount = 120
        let markedPlain = String(repeating: "**가**", count: unitCount)
        let displayPlain = String(repeating: "가", count: unitCount)
        let boldDisplay = NSAttributedString(
            string: displayPlain,
            attributes: MessageLineLimit.textAttributes(font: boldFont),
        )

        let markedLines = MessageLineLimit.lineCount(
            text: markedPlain, font: font, width: narrowWidth,
        )
        let displayLines = MessageLineLimit.lineCount(
            attributedText: boldDisplay, width: narrowWidth,
        )

        #expect(markedLines != displayLines)
        #expect(markedLines > displayLines)
    }

    // MARK: - collapsedSplit / lastLineText attributed

    @Test func `attributed collapsed split preserves bold runs and display plain`() {
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let boldEnd = text.utf16.count / 2
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: MessageLineLimit.textAttributes(font: font),
        )
        attributed.addAttribute(
            .font, value: boldFont, range: NSRange(location: 0, length: boldEnd),
        )

        let parts = MessageLineLimit.collapsedSplit(attributedText: attributed, width: narrowWidth)

        #expect(!parts.leading.string.isEmpty)
        #expect(!parts.trailing.string.isEmpty)
        #expect(text.hasPrefix(parts.leading.string))
        #expect(text.hasSuffix(parts.trailing.string))
        // 줄 시작 공백만 버리므로 두 조각 합 ≤ 표시 plain
        #expect(parts.leading.string.count + parts.trailing.string.count <= text.count)

        // leading 앞쪽이 원본 bold 범위와 겹치면 bold 런이 남아야 한다.
        if parts.leading.length > 0 {
            var range = NSRange()
            let leadingFont = parts.leading.attribute(
                .font, at: 0, effectiveRange: &range,
            ) as? UIFont
            #expect(leadingFont == boldFont)
        }

        // trailing 끝 글자가 원본 regular 구간이면 regular가 유지된다.
        if parts.trailing.length > 0 {
            var range = NSRange()
            let lastIndex = parts.trailing.length - 1
            let trailingFont = parts.trailing.attribute(
                .font, at: lastIndex, effectiveRange: &range,
            ) as? UIFont
            #expect(trailingFont == font)
        }
    }

    @Test func `attributed last line keeps bold runs and system font ellipsis`() {
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let attributed = NSAttributedString(
            string: text,
            attributes: MessageLineLimit.textAttributes(font: boldFont),
        )
        let reservedWidth: CGFloat = 40
        let line = MessageLineLimit.lastLineText(
            attributedText: attributed, width: narrowWidth, reservedWidth: reservedWidth,
        )

        #expect(line.string.hasSuffix(MessageLineLimit.ellipsis))
        #expect(line.string.count < text.count)

        // 본문 런은 bold 유지
        let bodyLength = line.length - MessageLineLimit.ellipsis.utf16.count
        #expect(bodyLength > 0)
        var bodyRange = NSRange()
        let bodyFont = line.attribute(.font, at: 0, effectiveRange: &bodyRange) as? UIFont
        #expect(bodyFont == boldFont)

        // 말줄임 토큰은 시스템 글꼴 — 한글 bold 런에 물리면 CJK 가운데 점이 된다.
        var ellipsisRange = NSRange()
        let ellipsisStart = line.length - MessageLineLimit.ellipsis.utf16.count
        let ellipsisFont = line.attribute(
            .font, at: ellipsisStart, effectiveRange: &ellipsisRange,
        ) as? UIFont
        let expected = UIFont.systemFont(ofSize: boldFont.pointSize)
        #expect(ellipsisFont == expected)
        #expect(ellipsisFont != boldFont)
    }

    @Test func `attributed last line ellipsis keeps body foreground color`() {
        // 사용자 말풍선 흰 글자 경로: 말줄임에 색이 없으면 UILabel 기본 .label로 검게 보인다.
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let bodyColor = UIColor.white
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: bodyColor,
                .paragraphStyle: MessageLineLimit.characterWrappingParagraphStyle,
            ],
        )
        let line = MessageLineLimit.lastLineText(
            attributedText: attributed, width: narrowWidth, reservedWidth: 40,
        )
        #expect(line.string.hasSuffix(MessageLineLimit.ellipsis))
        let ellipsisStart = line.length - MessageLineLimit.ellipsis.utf16.count
        let ellipsisColor = line.attribute(
            .foregroundColor, at: ellipsisStart, effectiveRange: nil,
        ) as? UIColor
        #expect(ellipsisColor == bodyColor)
    }

    @Test func `attributed last line without overflow returns full text`() {
        let text = "짧은 꼬리"
        let attributed = plainAttributed(text)
        let line = MessageLineLimit.lastLineText(
            attributedText: attributed, width: wideWidth, reservedWidth: 20,
        )

        #expect(line.string == text)
        #expect(line.length == attributed.length)
    }

    @Test func `attributed fitted width matches plain for single font within probe`() {
        let text = String(repeating: "가나다라마바사 ", count: 10)
        let maxWidth: CGFloat = 271
        let plain = MessageLineLimit.fittedWidth(text: text, font: font, maxWidth: maxWidth)
        let attributed = MessageLineLimit.fittedWidth(
            attributedText: plainAttributed(text), maxWidth: maxWidth,
        )
        #expect(plain == attributed)
    }

    @Test func `attributed collapsed aware width matches plain for single font`() {
        let text = Array(repeating: "ㅇ", count: MessageLineLimit.collapsedLines + 2)
            .joined(separator: "\n")
        let hugWidth: CGFloat = 16
        let plain = MessageLineLimit.collapsedAwareWidth(
            text: text, font: font, hugWidth: hugWidth, maxWidth: wideWidth,
        )
        let attributed = MessageLineLimit.collapsedAwareWidth(
            attributedText: plainAttributed(text),
            hugWidth: hugWidth,
            maxWidth: wideWidth,
            minimumWidthFont: font,
        )
        #expect(plain == attributed)
    }

    // MARK: - 파서 → 측정 파이프라인

    /// 수동 boldFont 조립이 아니라 `MessageInlineMarkdown` 산출물을 넣었을 때도
    /// collapsedSplit이 표시 plain을 유지하고 서식 런(bold/strike)을 보존한다.
    @Test func `parser output collapsed split preserves display plain and style runs`() {
        let unit = "**굵** ~~삭~~ "
        let markdown = String(repeating: unit, count: 80)
        let bodyColor = UIColor.darkText
        let attributed = MessageInlineMarkdown.attributedString(
            markdown: markdown, font: font, color: bodyColor,
        )

        #expect(attributed.string.contains("굵"))
        #expect(attributed.string.contains("삭"))
        #expect(!attributed.string.contains("*"))
        #expect(!attributed.string.contains("~"))

        let parts = MessageLineLimit.collapsedSplit(
            attributedText: attributed, width: narrowWidth,
        )
        #expect(!parts.leading.string.isEmpty)
        #expect(!parts.trailing.string.isEmpty)
        #expect(attributed.string.hasPrefix(parts.leading.string))
        #expect(attributed.string.hasSuffix(parts.trailing.string))

        // leading 어딘가에 bold 런이 남아야 한다(앞 단위가 **굵**).
        var foundBold = false
        parts.leading.enumerateAttribute(
            .font, in: NSRange(location: 0, length: parts.leading.length),
        ) { value, _, stop in
            guard let runFont = value as? UIFont else { return }
            if runFont.fontDescriptor.symbolicTraits.contains(.traitBold) {
                foundBold = true
                stop.pointee = true
            }
        }
        #expect(foundBold)

        // trailing(또는 leading)에 strike 런이 남아야 한다.
        let joined = NSMutableAttributedString(attributedString: parts.leading)
        joined.append(parts.trailing)
        var foundStrike = false
        joined.enumerateAttribute(
            .strikethroughStyle, in: NSRange(location: 0, length: joined.length),
        ) { value, _, stop in
            if let style = value as? Int, style != 0 {
                foundStrike = true
                stop.pointee = true
            }
        }
        #expect(foundStrike)
    }

    /// 파서 산출 → lastLineText: 말줄임이 본문 전경색을 물려받는다(사용자 흰 글자 회귀 봉인 + AI 경로).
    @Test func `parser output last line ellipsis inherits body foreground color`() {
        let markdown = String(repeating: "**가나다** ", count: 40)
        let bodyColor = UIColor.white
        let attributed = MessageInlineMarkdown.attributedString(
            markdown: markdown, font: font, color: bodyColor,
        )
        let line = MessageLineLimit.lastLineText(
            attributedText: attributed, width: narrowWidth, reservedWidth: 40,
        )
        #expect(line.string.hasSuffix(MessageLineLimit.ellipsis))
        let ellipsisStart = line.length - MessageLineLimit.ellipsis.utf16.count
        let ellipsisColor = line.attribute(
            .foregroundColor, at: ellipsisStart, effectiveRange: nil,
        ) as? UIColor
        #expect(ellipsisColor == bodyColor)
    }
}
