@testable import AIChat
import Testing
import UIKit

struct MessageInlineMarkdownTests {
    private let font = UIFont.systemFont(ofSize: 17)
    private let color = UIColor.label

    private func parse(_ markdown: String, color: UIColor? = nil) -> NSAttributedString {
        MessageInlineMarkdown.attributedString(
            markdown: markdown,
            font: font,
            color: color ?? self.color,
        )
    }

    // MARK: - Helpers

    /// 표시 문자열 범위에서 첫 font의 symbolicTraits가 `trait`를 포함하는지.
    private func hasFontTrait(
        _ attributed: NSAttributedString,
        substring: String,
        trait: UIFontDescriptor.SymbolicTraits,
    ) -> Bool {
        let full = attributed.string as NSString
        let range = full.range(of: substring)
        guard range.location != NSNotFound else { return false }
        guard let runFont = attributed.attribute(.font, at: range.location, effectiveRange: nil)
            as? UIFont
        else { return false }
        return runFont.fontDescriptor.symbolicTraits.contains(trait)
    }

    /// italic은 폰트 face가 아니라 `.obliqueness` 합성 기울기로 잠근다(한글 body 폰트 대응).
    private func hasObliqueness(_ attributed: NSAttributedString, substring: String) -> Bool {
        let full = attributed.string as NSString
        let range = full.range(of: substring)
        guard range.location != NSNotFound else { return false }
        guard let value = attributed.attribute(
            .obliqueness,
            at: range.location,
            effectiveRange: nil,
        ) as? CGFloat
        else { return false }
        return value != 0
    }

    private func hasStrikethrough(_ attributed: NSAttributedString, substring: String) -> Bool {
        let full = attributed.string as NSString
        let range = full.range(of: substring)
        guard range.location != NSNotFound else { return false }
        guard let style = attributed.attribute(
            .strikethroughStyle,
            at: range.location,
            effectiveRange: nil,
        ) as? Int
        else { return false }
        return style != 0
    }

    private func foregroundColor(
        _ attributed: NSAttributedString,
        substring: String,
    ) -> UIColor? {
        let full = attributed.string as NSString
        let range = full.range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil)
            as? UIColor
    }

    // MARK: - Cases

    @Test func `plain text is unchanged without style runs`() {
        let input = "안녕하세요 plain"
        let result = parse(input)
        #expect(result.string == input)

        // base font만 — bold/obliqueness/strikethrough 없음
        #expect(!hasFontTrait(result, substring: input, trait: .traitBold))
        #expect(!hasObliqueness(result, substring: input))
        #expect(!hasStrikethrough(result, substring: input))
    }

    @Test func `empty markdown yields empty attributed string with base attributes`() {
        let result = parse("")
        #expect(result.string.isEmpty)
        #expect(result.length == 0)
    }

    @Test func `double asterisk bold strips markers and applies bold trait`() {
        let result = parse("hello **bold** end")
        #expect(result.string == "hello bold end")
        #expect(!result.string.contains("*"))
        #expect(hasFontTrait(result, substring: "bold", trait: .traitBold))
    }

    @Test func `double underscore bold strips markers and applies bold trait`() {
        let result = parse("hello __bold__ end")
        #expect(result.string == "hello bold end")
        #expect(!result.string.contains("_"))
        #expect(hasFontTrait(result, substring: "bold", trait: .traitBold))
    }

    @Test func `single asterisk italic strips markers and applies obliqueness`() {
        let result = parse("hello *italic* end")
        #expect(result.string == "hello italic end")
        #expect(!result.string.contains("*"))
        #expect(hasObliqueness(result, substring: "italic"))
    }

    @Test func `single underscore italic strips markers and applies obliqueness`() {
        let result = parse("hello _italic_ end")
        #expect(result.string == "hello italic end")
        #expect(!result.string.contains("_"))
        #expect(hasObliqueness(result, substring: "italic"))
    }

    @Test func `korean italic applies obliqueness not only font trait`() {
        // body/한글 폰트는 italic face가 없어 trait 검사만으로는 화면에 안 보인다.
        let result = parse("이 문장에 *기울임 강조*가 포함됩니다.")
        #expect(result.string == "이 문장에 기울임 강조가 포함됩니다.")
        #expect(hasObliqueness(result, substring: "기울임 강조"))
        #expect(!hasObliqueness(result, substring: "이 문장에 "))
    }

    @Test func `tilde strike strips markers and applies strikethrough`() {
        let result = parse("hello ~~strike~~ end")
        #expect(result.string == "hello strike end")
        #expect(!result.string.contains("~"))
        #expect(hasStrikethrough(result, substring: "strike"))
    }

    /// 한 문장에 연속 서식이 섞여도 각 구간 outcome이 독립적으로 유지된다.
    @Test func `sequential bold italic and strike each keep their markers stripped and styles`() {
        let result = parse("**bold** and *italic* and ~~strike~~ done")
        #expect(result.string == "bold and italic and strike done")
        #expect(hasFontTrait(result, substring: "bold", trait: .traitBold))
        #expect(hasObliqueness(result, substring: "italic"))
        #expect(hasStrikethrough(result, substring: "strike"))
        #expect(!hasFontTrait(result, substring: " and ", trait: .traitBold))
        #expect(!hasObliqueness(result, substring: " and "))
        #expect(!hasStrikethrough(result, substring: " and "))
    }

    /// base color는 plain·서식 런 모두에 동일하게 붙는다(말풍선 발신자 색 경로).
    @Test func `base foreground color applies to plain and styled runs`() {
        let bodyColor = UIColor.white
        let result = parse("plain **bold** end", color: bodyColor)
        #expect(foregroundColor(result, substring: "plain") == bodyColor)
        #expect(foregroundColor(result, substring: "bold") == bodyColor)
        #expect(foregroundColor(result, substring: "end") == bodyColor)
    }

    /// 미완성 토큰은 크래시 없이 처리된다. 닫히지 않은 `**`는 리터럴로 남거나
    /// 파서가 무시하는 등 기본 동작 중 하나 — 어느 쪽이든 표시 문자열은 비어 있지 않다.
    @Test func `incomplete bold token does not crash`() {
        let input = "**열려만"
        let result = parse(input)
        // 강제 폴백이든 파서 통과든 동일 API 경로로 안전 반환.
        #expect(result.length > 0)
    }

    /// LocalizedStringKey 경로가 아니므로 `%`가 포맷 지정자로 깨지지 않는다.
    @Test func `percent sign in plain text is preserved literally`() {
        let input = "할인 50% 적용 / 진행률 100%"
        let result = parse(input)
        #expect(result.string == input)
    }
}
