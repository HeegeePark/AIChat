@testable import AIChat
import Testing
import UIKit

struct MessageLineLimitTests {
    private let font = UIFont.systemFont(ofSize: 17)
    private let wideWidth: CGFloat = 1000
    private let narrowWidth: CGFloat = 80
    private var leadingLines: Int {
        MessageLineLimit.collapsedLines - 1
    }

    // MARK: - 접힘 판정

    @Test func `short single line text is not collapsed`() {
        #expect(!MessageLineLimit.shouldCollapse(text: "안녕하세요", font: font, width: wideWidth))
    }

    @Test func `text wrapping past five lines at a narrow width is collapsed`() {
        let text = Array(repeating: "word", count: 200).joined(separator: " ")
        #expect(MessageLineLimit.shouldCollapse(text: text, font: font, width: narrowWidth))
    }

    @Test func `exactly five explicit lines is not collapsed`() {
        let text = Array(repeating: "line", count: 5).joined(separator: "\n")
        #expect(!MessageLineLimit.shouldCollapse(text: text, font: font, width: wideWidth))
    }

    @Test func `exactly six explicit lines is collapsed`() {
        let text = Array(repeating: "line", count: 6).joined(separator: "\n")
        #expect(MessageLineLimit.shouldCollapse(text: text, font: font, width: wideWidth))
    }

    @Test func `non positive width is not collapsed without crashing`() {
        #expect(!MessageLineLimit.shouldCollapse(text: "hello", font: font, width: 0))
        #expect(!MessageLineLimit.shouldCollapse(text: "hello", font: font, width: -10))
    }

    @Test func `empty string is not collapsed`() {
        #expect(!MessageLineLimit.shouldCollapse(text: "", font: font, width: wideWidth))
    }

    @Test func `long latin without spaces wraps by character at a narrow width`() {
        let text = String(repeating: "a", count: 80)
        #expect(MessageLineLimit.lineCount(text: text, font: font, width: narrowWidth) > 1)
    }

    // MARK: - 접힘 분할

    @Test func `leading part fills the available lines without exceeding them`() {
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let parts = MessageLineLimit.collapsedSplit(text: text, font: font, width: narrowWidth)

        // 줄 경계에서 정확히 나뉘므로 앞 조각은 딱 그 줄 수만큼이다
        #expect(MessageLineLimit.lineCount(text: parts.leading, font: font, width: narrowWidth) == leadingLines)
        #expect(!parts.trailing.isEmpty)
    }

    @Test func `text fitting the leading lines is not split`() {
        let text = "짧은 메시지"
        let parts = MessageLineLimit.collapsedSplit(text: text, font: font, width: wideWidth)

        #expect(parts.leading == text)
        #expect(parts.trailing.isEmpty)
    }

    @Test func `split keeps the original text intact`() {
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let parts = MessageLineLimit.collapsedSplit(text: text, font: font, width: narrowWidth)

        #expect(!parts.leading.isEmpty)
        #expect(!parts.trailing.isEmpty)
        #expect(text.hasPrefix(parts.leading))
        #expect(text.hasSuffix(parts.trailing))
        // 줄 시작의 공백만 버려지므로 두 조각의 합은 원문을 넘지 않는다
        #expect(parts.leading.count + parts.trailing.count <= text.count)
    }

    @Test func `split does not break grapheme clusters`() {
        let text = String(repeating: "👨‍👩‍👧‍👦한글🇰🇷", count: 40)
        let parts = MessageLineLimit.collapsedSplit(text: text, font: font, width: narrowWidth)

        // 결합 문자 중간을 잘랐다면 prefix/suffix 일치가 깨진다
        #expect(text.hasPrefix(parts.leading))
        #expect(text.hasSuffix(parts.trailing))
    }

    @Test func `trailing part does not start with whitespace`() {
        let text = Array(repeating: "word", count: 200).joined(separator: " ")
        let parts = MessageLineLimit.collapsedSplit(text: text, font: font, width: narrowWidth)

        #expect(parts.trailing.first?.isWhitespace == false)
    }

    // MARK: - 마지막 줄

    @Test func `last line ends with an ellipsis when the text overflows`() {
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let line = MessageLineLimit.lastLineText(
            text: text, font: font, width: narrowWidth, reservedWidth: 20,
        )

        #expect(line.hasSuffix(MessageLineLimit.ellipsis))
        #expect(line.count < text.count)
    }

    @Test func `last line keeps text that fits without an ellipsis`() {
        let line = MessageLineLimit.lastLineText(
            text: "짧은 꼬리", font: font, width: wideWidth, reservedWidth: 20,
        )

        #expect(line == "짧은 꼬리")
    }

    @Test func `last line drops trailing whitespace before the ellipsis`() {
        let text = Array(repeating: "word", count: 100).joined(separator: " ")
        let line = MessageLineLimit.lastLineText(
            text: text, font: font, width: narrowWidth, reservedWidth: 20,
        )

        #expect(line.dropLast().last?.isWhitespace == false)
    }

    @Test func `last line fits in the width left after the reserved area`() {
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let reservedWidth: CGFloat = 40
        let line = MessageLineLimit.lastLineText(
            text: text, font: font, width: narrowWidth, reservedWidth: reservedWidth,
        )

        // 이 불변식이 깨지면 "더 보기" 자리를 침범한다
        #expect(MessageLineLimit.textWidth(line, font: font) <= narrowWidth - reservedWidth)
    }

    @Test func `non positive width keeps the whole text in the leading part`() {
        let parts = MessageLineLimit.collapsedSplit(text: "hello", font: font, width: 0)

        #expect(parts.leading == "hello")
        #expect(parts.trailing.isEmpty)
    }

    // MARK: - hug 폭 (prefix 단축)

    /// 말풍선 폭 상한. 실기기(iPhone 15 Pro Max) AI 말풍선 상한과 같은 자릿수.
    private static let hugMaxWidth: CGFloat = 271

    private static let probeSamples = [
        "안녕", "안녕하세요 반갑습니다",
        "가나다라마바사아자차카타파하 ",
        "This is an english sentence that keeps going and going. ",
        "illillil.,;: iiillll.. ",
        "AI 응답 streaming 중 bubble width를 확인하는 mixed 문장입니다. ",
        "줄바꿈\n포함\n문장 ",
    ]

    /// probe 길이 안에서는 근사가 아니라 **전체 조판과 동일**해야 한다.
    /// 짧은 말풍선의 hug는 눈에 바로 띄므로 이 구간은 오차를 허용하지 않는다.
    @Test(arguments: probeSamples)
    func `fitted width is exact for text within the probe length`(base: String) {
        let long = String(repeating: base, count: 80)
        for length in [0, 1, 5, 20, 60, 150, 399, MessageLineLimit.widthProbeLength] {
            guard length <= long.count else { continue }
            let text = String(long.prefix(length))

            #expect(
                MessageLineLimit.fittedWidth(text: text, font: font, maxWidth: Self.hugMaxWidth)
                    == MessageLineLimit.boundedWidth(of: text, font: font, maxWidth: Self.hugMaxWidth),
                "length \(length) of \(base.debugDescription)",
            )
        }
    }

    /// probe를 넘는 장문은 근사다. 허용치를 못 박아 두지 않으면 상수를 줄일 때 조용히 나빠진다.
    /// 실측 최대 2.5pt(432조합)라 4pt는 텍스트 엔진 변화를 감안한 여유다.
    @Test(arguments: probeSamples)
    func `fitted width stays within tolerance beyond the probe length`(base: String) {
        let long = String(repeating: base, count: 200)
        for length in [800, 1600, 2500] {
            guard length <= long.count else { continue }
            let text = String(long.prefix(length))
            let fitted = MessageLineLimit.fittedWidth(
                text: text, font: font, maxWidth: Self.hugMaxWidth,
            )
            let full = MessageLineLimit.boundedWidth(
                of: text, font: font, maxWidth: Self.hugMaxWidth,
            )

            #expect(abs(fitted - full) <= 4, "length \(length) of \(base.debugDescription): \(fitted) vs \(full)")
        }
    }

    // MARK: - 확정 블록 분할

    private static let blockMinLength = 200

    /// 샘플마다 길이가 제각각이라(2자 ~ 56자) 목표 길이까지 채운 뒤 자른다.
    /// 짧은 샘플이 블록 최소 길이에 못 미치면 블록이 하나도 안 생겨 계약을 검증하지 못한다.
    private func streamSample(_ base: String, length: Int = 900) -> String {
        String(String(repeating: base, count: length / base.count + 1).prefix(length))
    }

    /// 실제 스트리밍처럼 한 글자씩 붙이며 확정 블록을 쌓는다.
    /// 전체를 한 번에 넘기면 첫 호출이 마지막 줄만 빼고 다 얼려버려 프로덕션 경로와 달라진다.
    private func settledBlocks(of text: String, width: CGFloat) -> (blocks: [String], tail: String) {
        var blocks: [String] = []
        var tail = ""
        for character in text {
            tail.append(character)
            if let split = MessageLineLimit.settledSplit(
                tail: tail, font: font, width: width, minLength: Self.blockMinLength,
            ) {
                blocks.append(split.block)
                tail = split.tail
            }
        }
        return (blocks, tail)
    }

    /// 이 계약이 깨지면 스트리밍 말풍선의 줄바꿈이 완료된 말풍선과 달라진다.
    /// 블록을 따로 조판해도 원문과 줄 경계가 같아야 한다는 것이 A안 전체의 전제다.
    /// (높이까지 같은지는 라벨이 필요해 시뮬레이터에서 따로 확인했다 — 단일 대비 2~5pt)
    @Test(arguments: probeSamples)
    func `settled blocks reproduce the line breaks of a single typeset`(base: String) {
        let text = streamSample(base)
        let (blocks, tail) = settledBlocks(of: text, width: narrowWidth)

        #expect(blocks.count > 1, "블록이 안 쪼개지면 계약을 검증하지 못한다")
        let stacked = (blocks + [tail]).reduce(0) {
            $0 + MessageLineLimit.lineCount(text: $1, font: font, width: narrowWidth)
        }
        #expect(stacked == MessageLineLimit.lineCount(text: text, font: font, width: narrowWidth))
    }

    @Test(arguments: probeSamples)
    func `settled blocks and tail keep every non newline character`(base: String) {
        let text = streamSample(base)
        let (blocks, tail) = settledBlocks(of: text, width: narrowWidth)

        // 블록 끝 개행만 빠지므로 그 외 글자는 순서까지 그대로여야 한다
        let joined = (blocks + [tail]).joined()
        #expect(
            joined.filter { !$0.isNewline } == text.filter { !$0.isNewline },
        )
    }

    /// 블록 끝에 개행이 남으면 라벨이 빈 줄을 하나 더 그린다(실측 +23pt).
    @Test(arguments: probeSamples)
    func `settled block never ends with a newline`(base: String) {
        let text = streamSample(base)
        let (blocks, _) = settledBlocks(of: text, width: narrowWidth)

        #expect(blocks.allSatisfy { !$0.hasSuffix("\n") })
    }

    @Test func `settled split waits until the tail reaches the minimum length`() {
        let text = String(repeating: "가", count: Self.blockMinLength - 1)

        #expect(MessageLineLimit.settledSplit(
            tail: text, font: font, width: narrowWidth, minLength: Self.blockMinLength,
        ) == nil)
    }

    /// 아직 한 줄도 안 끝났으면 얼릴 게 없다 — 마지막 줄은 계속 자랄 수 있어서 확정하면 안 된다.
    @Test func `settled split returns nil while no line has completed`() {
        let text = String(repeating: "a", count: 300)

        #expect(MessageLineLimit.settledSplit(
            tail: text, font: font, width: 10000, minLength: Self.blockMinLength,
        ) == nil)
    }

    /// 스트리밍은 글자가 늘어나는 과정이라, 폭이 중간에 줄면 말풍선이 눈에 띄게 흔들린다.
    @Test func `fitted width never shrinks as the text grows`() {
        let long = String(repeating: "성능 측정을 위한 한글 문장입니다. ", count: 60)
        var previous: CGFloat = 0
        for length in stride(from: 0, through: min(1200, long.count), by: 7) {
            let width = MessageLineLimit.fittedWidth(
                text: String(long.prefix(length)), font: font, maxWidth: Self.hugMaxWidth,
            )

            #expect(width >= previous, "length \(length): \(width) < \(previous)")
            previous = width
        }
    }

    // MARK: - 접힘 인지 폭 (한 글자짜리 줄이 반복되면 hug 폭이 버튼보다 좁아진다)

    @Test func `collapsed aware width floors a narrow hug width so the more button fits`() {
        let text = Array(repeating: "ㅇ", count: 6).joined(separator: "\n")
        let hugWidth: CGFloat = 16 // 한 글자 폭 — 실측 버그 재현

        let width = MessageLineLimit.collapsedAwareWidth(
            text: text, font: font, hugWidth: hugWidth, maxWidth: wideWidth,
        )

        #expect(width >= MessageLineLimit.minimumCollapsedWidth(font: font))
    }

    @Test func `collapsed aware width does not exceed the bubble max width`() {
        let text = Array(repeating: "ㅇ", count: 6).joined(separator: "\n")

        let width = MessageLineLimit.collapsedAwareWidth(
            text: text, font: font, hugWidth: 16, maxWidth: 30,
        )

        #expect(width <= 30)
    }

    @Test func `collapsed aware width leaves non collapsing text at its natural hug width`() {
        let text = "짧은 메시지"
        let hugWidth = MessageLineLimit.textWidth(text, font: font) + 1

        let width = MessageLineLimit.collapsedAwareWidth(
            text: text, font: font, hugWidth: hugWidth, maxWidth: wideWidth,
        )

        #expect(width == hugWidth)
    }

    @Test func `last line keeps a leading character before the ellipsis once width is floored`() {
        // 고친 폭 없이 이 시나리오를 재현하면 lastLine이 "…" 하나만 남아 버튼이 세로로 쪼개졌다.
        let text = Array(repeating: "ㅇ", count: 6).joined(separator: "\n")
        let width = MessageLineLimit.collapsedAwareWidth(
            text: text, font: font, hugWidth: 16, maxWidth: wideWidth,
        )
        let parts = MessageLineLimit.collapsedSplit(text: text, font: font, width: width)
        let reserved = MessageLineLimit.textWidth(
            MessageLineLimit.moreLabelText, font: MessageLineLimit.moreLabelFont(from: font),
        ) + MessageLineLimit.moreLabelSpacing

        let lastLine = MessageLineLimit.lastLineText(
            text: parts.trailing, font: font, width: width, reservedWidth: reserved,
        )

        #expect(lastLine != MessageLineLimit.ellipsis)
    }
}

/// "더 보기" 레이블 폰트(semibold)와 그 폭 예약 계약. `MessageLineLimitTests`와 분리한 건
/// 그쪽이 `type_body_length` 상한에 닿아서다.
struct MoreLabelFontTests {
    private let font = UIFont.systemFont(ofSize: 17)
    /// 실기기 말풍선 상한(화면 폭의 75%)에 가까운 폭. 예약 폭이 걸린 계산은 이 폭으로 잰다.
    private let bubbleWidth: CGFloat = 250

    private var reservedWidth: CGFloat {
        MessageLineLimit.textWidth(
            MessageLineLimit.moreLabelText, font: MessageLineLimit.moreLabelFont(from: font),
        ) + MessageLineLimit.moreLabelSpacing
    }

    /// 예약 폭은 렌더와 **같은** 폰트로 재야 한다. 예약이 실제 렌더보다 좁으면 UILabel이 이미 붙은 `…`를
    /// 한 번 더 tail truncate해서 CJK 가운데 점(⋯)이 나온다.
    ///
    /// `narrowWidth`(80)가 아니라 실제 말풍선에 가까운 폭을 쓴다 — 80에서는 "더 보기"를 예약하고 나면
    /// 남는 폭이 한글 한 글자보다 좁아지는데, CoreText는 한 줄에 최소 한 글자를 넣으므로 weight와 무관하게
    /// 예약을 넘긴다. 그 축퇴 케이스는 이 테스트의 관심사가 아니다.
    @Test func `last line fits in the width left after a semibold reserved area`() {
        let text = String(repeating: "가나다라마바사아자차", count: 20)
        let line = MessageLineLimit.lastLineText(
            text: text, font: font, width: bubbleWidth, reservedWidth: reservedWidth,
        )

        // 마지막 줄 원문은 본문 폰트로 그려지므로 본문 폰트로 잰다
        #expect(line.hasSuffix(MessageLineLimit.ellipsis))
        #expect(MessageLineLimit.textWidth(line, font: font) <= bubbleWidth - reservedWidth)
    }

    @Test func `more label font keeps the body point size and gains weight`() {
        let moreFont = MessageLineLimit.moreLabelFont(from: font)

        // Dynamic Type: 본문에서 파생하므로 크기가 같아야 한다 (고정 pt 폰트면 여기서 깨진다)
        #expect(moreFont.pointSize == font.pointSize)
        #expect(moreFont != font)
    }

    /// 말풍선 폭 하한도 레이블 폭을 입력으로 받는다. 레이블 항만 semibold이고
    /// `ellipsis`·글자 하나 여유는 본문 폰트라, 하한은 본문 폰트로만 잰 값보다 넓을 수 없다.
    @Test func `minimum collapsed width reserves the semibold label`() {
        let minimum = MessageLineLimit.minimumCollapsedWidth(font: font)

        #expect(minimum > reservedWidth)
        #expect(minimum >= reservedWidth + MessageLineLimit.textWidth(
            MessageLineLimit.ellipsis, font: font,
        ))
    }
}
