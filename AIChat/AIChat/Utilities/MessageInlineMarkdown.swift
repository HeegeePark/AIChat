import Foundation
import UIKit

/// 인라인 마크다운을 UILabel/CoreText에 바로 쓸 수 있는 `NSAttributedString`으로 바꾼다.
///
/// - 파싱: `AttributedString(markdown:options:)` + `.inlineOnlyPreservingWhitespace`.
///   블록(헤딩·리스트) 레이아웃·링크 탭 UI는 열지 않는다.
/// - 지원 런: bold / italic / strikethrough. 밑줄·코드·중첩 서식은 보장하지 않는다.
/// - italic은 폰트 face의 slant가 아니라 **`.obliqueness`** 로 합성한다. body/한글 폰트는
///   italic face가 없어 trait slant만으로는 화면에 기울임이 안 보인다.
/// - 실패·미지원 입력은 base font·color 단일 속성 plain 문자열로 폴백한다(강제 언래핑 없음).
/// - 미완성 토큰(예: `**열려만`): Foundation 파서가 크래시 없이 처리한다. 닫히지 않은
///   마커는 리터럴로 남거나 파서 기본 동작에 따른다 — 스트리밍 중 plain 경로를 쓰는 쪽과
///   맞춰 완료 시점 1회 파싱을 전제로 한다.
/// - `paragraphStyle`·`lineSpacing`은 **넣지 않는다**. 측정(`MessageLineLimit`)·렌더
///   (`BubblePlainTextLabel`)가 `.byCharWrapping`/행간을 덮어쓸 수 있게 둔다.
/// - `LocalizedStringKey` 경로가 아니므로 `%` 등 포맷 문자가 깨지지 않는다.
nonisolated enum MessageInlineMarkdown {
    /// - Parameters:
    ///   - markdown: 원문(마커 포함 가능). 표시 문자열은 마커가 제거된 형태다.
    ///   - font: base `UIFont`. bold 런은 weight trait, italic은 `.obliqueness`.
    ///   - color: base 전경색. 모든 런에 동일하게 적용한다.
    static func attributedString(
        markdown: String,
        font: UIFont,
        color: UIColor,
    ) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return plainAttributedString(markdown, font: font, color: color)
        }
        return nsAttributedString(from: parsed, baseFont: font, color: color)
    }

    // MARK: - Private

    /// 합성 이탤릭 기울기. 너무 크면 자간이 깨지고, 너무 작으면 한글에서 안 보인다.
    private static let italicObliqueness: CGFloat = 0.25

    private static func plainAttributedString(
        _ text: String,
        font: UIFont,
        color: UIColor,
    ) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
            ],
        )
    }

    private static func nsAttributedString(
        from parsed: AttributedString,
        baseFont: UIFont,
        color: UIColor,
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            guard !text.isEmpty else { continue }

            let intent = run.inlinePresentationIntent
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(for: intent, base: baseFont),
                .foregroundColor: color,
            ]
            if let intent, intent.contains(.emphasized) {
                // 한글·body 폰트는 italic face가 없다. trait slant는 화면에 안 나와
                // UILabel/CoreText가 그리는 합성 기울기(.obliqueness)를 쓴다.
                attributes[.obliqueness] = italicObliqueness
            }
            if let intent, intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        // 빈 원문 등 runs가 없으면 plain 폴백과 동일 계약 유지.
        if result.length == 0 {
            return plainAttributedString(String(parsed.characters), font: baseFont, color: color)
        }
        return result
    }

    /// bold만 폰트 face/weight로 표현한다. italic face는 여기서 만들지 않는다.
    private static func font(
        for intent: InlinePresentationIntent?,
        base: UIFont,
    ) -> UIFont {
        guard let intent, intent.contains(.stronglyEmphasized) else { return base }

        if let boldDescriptor = base.fontDescriptor.withSymbolicTraits(
            base.fontDescriptor.symbolicTraits.union(.traitBold),
        ) {
            return UIFont(descriptor: boldDescriptor, size: base.pointSize)
        }

        let traitDict: [UIFontDescriptor.TraitKey: Any] = [
            .weight: UIFont.Weight.bold,
        ]
        let descriptor = base.fontDescriptor.addingAttributes([.traits: traitDict])
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}
