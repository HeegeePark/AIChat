import CoreText
import UIKit

nonisolated enum MessageLineLimit {
    /// 접힌 말풍선이 보여주는 줄 수이자 접힘 판정 기준 — 이 줄 수에 들어가지 않으면 접는다.
    /// 정책: 5줄을 초과하면 접는다 → `lineCount > 5`이므로 상수는 5. 접힌 표시도 같은 5줄.
    /// "언제 접는가"와 "몇 줄을 보여주는가"가 같은 질문이라 상수도 하나다.
    static let collapsedLines = 5

    /// 렌더(`UILabel`)와 동일한 글자 단위 줄바꿈.
    /// 줄 수 판정에는 행간을 넣지 않는다 — 화면 `lineSpacing`은 시각만 바꾸고 줄 수와 무관하다.
    static var characterWrappingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        return style
    }

    /// 화면에 그리는 원문과 같은 문자열·폰트에 쓸 attributes (측정·hug 공용).
    static func textAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .paragraphStyle: characterWrappingParagraphStyle,
        ]
    }

    // MARK: - 접힘 판정

    /// - Parameter text: 화면에 그리는 원문과 동일해야 한다 (`Message.text` 또는 실패 카피).
    static func shouldCollapse(text: String, font: UIFont, width: CGFloat) -> Bool {
        shouldCollapse(attributedText: plainAttributed(text, font: font), width: width)
    }

    /// 표시용 plain + 런 속성이 반영된 문자열로 접힘 여부를 판정한다.
    /// 문법 마커가 빠진 표시 문자열을 넣어야 한다 — 마커 포함 원문으로 재면 줄 수가 어긋난다.
    static func shouldCollapse(attributedText: NSAttributedString, width: CGFloat) -> Bool {
        lineCount(attributedText: attributedText, width: width) > collapsedLines
    }

    static func lineCount(text: String, font: UIFont, width: CGFloat) -> Int {
        lineCount(attributedText: plainAttributed(text, font: font), width: width)
    }

    /// 표시 문자열 인덱스 기준 줄 수. 런별 font/strikethrough 폭이 반영된다.
    static func lineCount(attributedText: NSAttributedString, width: CGFloat) -> Int {
        typesetLines(attributedText: attributedText, width: width).count
    }

    // MARK: - 접힘 분할

    /// 접힌 말풍선을 그릴 두 조각으로 나눈다.
    /// `leading`은 전체 폭으로 `collapsedLines - 1`줄까지, `trailing`은 마지막 줄에 그릴 나머지 전부다.
    /// 이미 `collapsedLines - 1`줄 안에 들어가는 텍스트면 `trailing`은 비어 있다.
    ///
    /// 여기서는 줄 경계로 나누기만 한다. `trailing`을 마지막 줄 폭에 맞춰 자르고 `…`를 붙이는 건
    /// `lastLineText`의 몫이다.
    static func collapsedSplit(
        text: String, font: UIFont, width: CGFloat,
    ) -> (leading: String, trailing: String) {
        let parts = collapsedSplit(attributedText: plainAttributed(text, font: font), width: width)
        return (parts.leading.string, parts.trailing.string)
    }

    static let ellipsis = "…"
    /// "더 보기" 라벨과 그 앞 간격. `CollapsedBubbleText`의 실제 버튼과 값을 공유해야
    /// hug 폭 계산(`minimumCollapsedWidth`)과 레이아웃 예약 폭이 어긋나지 않는다.
    static let moreLabelText = "더 보기"
    static let moreLabelSpacing: CGFloat = 4

    /// "더 보기" 레이블 폰트 — 본문에서 weight만 올려 탭 가능한 컨트롤임을 보여준다.
    /// 본문 폰트에서 파생하므로 Dynamic Type 크기를 그대로 물려받는다. 고정 pt
    /// `systemFont(ofSize:weight:)`를 박으면 본문만 커지고 버튼은 그대로인 회귀가 난다.
    ///
    /// 레이블 폭을 재는 쪽(`minimumCollapsedWidth`, `CollapsedBubbleText`의 예약 폭)은 모두 이 폰트를
    /// 써야 한다. 한글은 weight를 올려도 advance가 그대로고(공백만 미세하게 좁아짐) 겹침도 `HStack`이
    /// 구조적으로 막지만, 그 안전은 이 문자열·이 폰트에서만 참인 우연이다. 예약이 렌더보다 좁아지면
    /// UILabel이 `…`를 한 번 더 잘라 CJK 가운데 점(⋯)이 된다.
    static func moreLabelFont(from base: UIFont) -> UIFont {
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold],
        ])
        // size: 0은 descriptor가 들고 있는 pointSize를 그대로 유지한다.
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// 접힌 말풍선이 "더 보기" 버튼 + 말줄임 + 글자 하나를 함께 담을 최소 폭.
    static func minimumCollapsedWidth(font: UIFont) -> CGFloat {
        textWidth(moreLabelText, font: moreLabelFont(from: font)) + moreLabelSpacing
            + textWidth(ellipsis, font: font) + font.pointSize
    }

    /// 카카오톡식 hug 폭(`hugWidth`)이 접힘에 필요한 최소 폭보다 좁으면 그 폭을 그대로 못 쓴다 —
    /// 한 글자짜리 줄이 반복되는 문장은 hug 폭이 글자 하나 폭까지 좁아지는데, 그 폭으로 접힌 말풍선을
    /// 그리면 "더 보기" 버튼이 밀려날 자리가 없어 세로로 한 글자씩 쪼개진다.
    /// `collapsedLines`를 넘는 텍스트에 한해 최소 폭까지 넓히되, 넓힌 폭에서 오히려 접을 필요가
    /// 없어지면(넓어진 폭에서 줄바꿈이 줄어드는 경우) 원래 hug 폭을 그대로 돌려준다 — 그 경우 버튼 자체가
    /// 없으니 억지로 넓힐 이유가 없다.
    static func collapsedAwareWidth(text: String, font: UIFont, hugWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        collapsedAwareWidth(
            attributedText: plainAttributed(text, font: font),
            hugWidth: hugWidth,
            maxWidth: maxWidth,
            minimumWidthFont: font,
        )
    }

    // MARK: - 마지막 줄

    /// 마지막 줄에 그릴 문자열. `reservedWidth`("더 보기" 자리)를 뺀 폭에 들어가는 만큼만 남기고 `…`를 붙인다.
    ///
    /// 잘림을 SwiftUI `truncationMode(.tail)`에 맡기지 않는 이유: 잘림 토큰의 글꼴은 **잘린 지점 런의
    /// 글꼴**을 따라간다. 한글 한가운데서 잘리면 토큰도 한글 글꼴(Apple SD Gothic Neo)이 되는데, 이 글꼴의
    /// `…`는 CJK 관례대로 가운데 점(⋯)이라 같은 말풍선인데 잘린 위치에 따라 말줄임표 모양이 달라진다.
    /// 문자열에 직접 넣은 `…`는 한글 바로 뒤라도 SF로 배정돼(글리프 커버리지 기준) 항상 베이스라인이다.
    static func lastLineText(
        text: String, font: UIFont, width: CGFloat, reservedWidth: CGFloat,
    ) -> String {
        lastLineText(
            attributedText: plainAttributed(text, font: font),
            width: width,
            reservedWidth: reservedWidth,
        ).string
    }

    // MARK: - 스트리밍 확정 블록

    /// 스트리밍 중 앞부분을 불변 라벨로 얼리기 위해, `tail`을 확정 블록과 남는 tail로 나눈다.
    ///
    /// `tail`이 `minLength` 이상 쌓였을 때만, **마지막 줄을 남기고** 그 앞까지를 확정한다.
    /// 마지막 줄은 뒤에 글자가 더 붙으면 아직 바뀔 수 있어서 얼리면 안 된다.
    /// 아직 짧거나 한 줄도 안 끝났으면(줄바꿈이 불가능한 초장문 한 줄) `nil` — 얼리지 않는다.
    ///
    /// 경계가 CoreText 줄 시작이라 잘라 낸 조각을 따로 조판해도 줄바꿈이 원문과 같다.
    /// 글자 단위 줄바꿈은 greedy라 줄 시작점만 같으면 이후 경계가 그대로 재현된다
    /// (실측: 한글·영문·개행·공백없음 4종에서 단일 라벨과 줄 수가 완전히 일치).
    static func settledSplit(
        tail: String, font: UIFont, width: CGFloat, minLength: Int,
    ) -> (block: String, tail: String)? {
        guard tail.utf16.count >= minLength else { return nil }

        let lines = typesetLines(attributedText: plainAttributed(tail, font: font), width: width)
        guard lines.count > 1, let lastLine = lines.last else { return nil }

        let cut = String.Index(utf16Offset: CTLineGetStringRange(lastLine).location, in: tail)
        guard cut > tail.startIndex else { return nil }

        var block = tail[..<cut]
        // 줄 경계로 자르면 조각 끝에 개행이 남는데, 라벨은 그걸 빈 줄 하나로 더 그린다(실측 +23pt).
        // 블록 경계 자체가 줄을 끝내므로 떼어낸다.
        if block.hasSuffix("\n") {
            block = block.dropLast()
        }
        return (String(block), String(tail[cut...]))
    }

    // MARK: - hug 폭

    /// hug 폭을 이 앞부분만 보고 정한다. 길이·기기폭·폰트·문자종을 훑은 실측(432조합)에서
    /// 400자면 전체 조판과의 차이가 최대 2.5pt(상한 250pt 기준 1%)였고, 그중에서도 6조합만 달랐다.
    /// 줄이면 오차 빈도가 늘고(200자: 42조합) 키우면 스트리밍 틱당 비용이 는다(800자: 3배).
    static let widthProbeLength = 400

    /// 카카오톡식 hug 폭 — `min(콘텐츠 폭, maxWidth)`.
    ///
    /// **앞 `widthProbeLength`자만 조판한 근사값이다.** 스트리밍 말풍선은 글자마다 이 계산을 다시
    /// 부르는데 전체를 재면 글자 수에 대해 O(n²)가 되기 때문이다(실측: 2500자에서 회당 4.2ms).
    /// 여러 줄로 접히는 텍스트의 hug 폭은 "가장 넓은 줄"이라 앞부분만으로 사실상 결정되고,
    /// 근사로 인한 차이는 위 상수 주석의 범위 안이다.
    ///
    /// 근사여도 화면이 어긋나지 않는 이유: 접힘 판정·분할·`UILabel` 줄바꿈이 모두 여기서 나온 **같은 폭**을
    /// 쓴다. 말풍선이 몇 pt 좁아질 뿐 잘림이나 측정·렌더 불일치는 생기지 않는다.
    /// 부수 효과로 스트리밍 중 폭이 미세하게 자라던 것도 앞부분에서 고정된다.
    static func fittedWidth(text: String, font: UIFont, maxWidth: CGFloat) -> CGFloat {
        fittedWidth(attributedText: plainAttributed(text, font: font), maxWidth: maxWidth)
    }

    /// 단축 없이 전체를 조판한 hug 폭. `fittedWidth`의 정답지이자 짧은 텍스트에서의 동일 경로.
    static func boundedWidth(of text: String, font: UIFont, maxWidth: CGFloat) -> CGFloat {
        boundedWidth(of: plainAttributed(text, font: font), maxWidth: maxWidth)
    }

    /// 한 줄로 조판했을 때의 폭. "더 보기" 예약 폭 등 레이아웃 계산에 쓴다.
    static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: textAttributes(font: font)),
        )
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    // MARK: - 내부 조판

    /// plain 공개 API가 위임할 단일 font attributed.
    static func plainAttributed(_ text: String, font: UIFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: textAttributes(font: font))
    }

    /// 측정 시 paragraph를 고정한다 — `lineBreakMode = byCharWrapping`, lineSpacing 없음.
    /// font·strikethrough 등 호출자 런 속성은 유지한다.
    static func preparingForMeasurement(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(
            .paragraphStyle,
            value: characterWrappingParagraphStyle,
            range: NSRange(location: 0, length: mutable.length),
        )
        return mutable
    }

    static func measurementBaseFont(of attributed: NSAttributedString) -> UIFont {
        guard attributed.length > 0 else {
            return UIFont.preferredFont(forTextStyle: .body)
        }
        var range = NSRange()
        if let font = attributed.attribute(.font, at: 0, effectiveRange: &range) as? UIFont {
            return font
        }
        return UIFont.preferredFont(forTextStyle: .body)
    }

    static func attributedSubstring(
        _ attributed: NSAttributedString, utf16Range: NSRange,
    ) -> NSAttributedString {
        guard utf16Range.length > 0, utf16Range.location >= 0 else {
            return NSAttributedString()
        }
        let end = utf16Range.location + utf16Range.length
        guard end <= attributed.length else {
            return NSAttributedString()
        }
        return attributed.attributedSubstring(from: utf16Range)
    }

    /// 주어진 폭에서 조판된 줄 조각들.
    ///
    /// `NSString.boundingRect` 높이 ÷ `lineHeight` 방식은 쓰지 않는다 — 줄 경계를 CoreText가
    /// 직접 주고, UILabel `.byCharWrapping`과 같은 paragraph를 쓰면 측정·렌더가 맞는다.
    /// 단일 font attributes·다중 런 attributed 모두 이 경로를 탄다.
    static func typesetLines(attributedText: NSAttributedString, width: CGFloat) -> [CTLine] {
        guard width > 0, attributedText.length > 0 else { return [] }

        let measured = preparingForMeasurement(attributedText)
        let framesetter = CTFramesetterCreateWithAttributedString(measured)
        // 높이 제한이 있으면 넘치는 줄이 잘려 나간다. greatestFiniteMagnitude는 CoreText 내부 계산에서
        // 안전하지 않아 충분히 큰 유한값을 쓴다(1pt 줄 기준으로도 백만 줄).
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: width, height: 1_000_000), transform: nil,
        )
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return CTFrameGetLines(frame) as? [CTLine] ?? []
    }
}
