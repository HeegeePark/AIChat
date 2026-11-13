import SwiftUI
import UIKit

/// 스트리밍 중인 말풍선 본문. 확정된 앞부분을 불변 블록 라벨로 얼리고 마지막 tail만 갱신한다.
///
/// 라벨 하나로 그리면 글자마다 **전체** 문자열을 다시 조판하고 다시 그린다. 그래서 틱당 비용이
/// 길이에 비례하고 누적이 O(n²)가 된다 (실측: 2500자에서 틱당 `sizeThatFits` 2.9ms + `drawText` 1.6ms,
/// 스트리밍 중 시뮬레이터 CPU 코어 하나의 47%).
/// 확정 블록은 값이 안 바뀌어 `updateUIView`가 조기 반환하므로 재조판·재드로우가 없다.
/// 그래서 틱당 비용이 tail 길이로 상한이 걸리고 누적이 O(n)이 된다.
struct StreamingBubbleText: View {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let width: CGFloat
    let lineSpacing: CGFloat

    /// 블록 하나의 목표 길이. 작을수록 틱당 비용이 낮지만 라벨 수가 늘어 높이 오차가 누적된다 —
    /// 라벨마다 intrinsic height에 `ceil`이 따로 걸리기 때문이다.
    /// 실측(2500자): 400자면 블록 6~7개에 단일 라벨 대비 2~5pt, 200자면 12~15개에 4~11pt.
    private static let blockLength = 400

    @State private var blocks: [SettledBlock] = []
    @State private var tail = ""
    /// `blocks`가 소비한 원문 Character 수. 다음 tail을 원문에서 잘라내는 기준이다.
    @State private var consumed = 0

    var body: some View {
        // 블록 사이 간격은 라벨 내부 줄 간격과 같아야 한 라벨로 그린 것과 세로 리듬이 맞는다.
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(blocks) { block in
                label(block.text)
            }
            if !tail.isEmpty {
                label(tail)
            }
        }
        .onChange(of: text, initial: true) { _, newText in
            advance(to: newText)
        }
        .onChange(of: width) { _, _ in
            // 폭이 바뀌면(Dynamic Type·회전) 줄 경계가 달라져 기존 블록 경계가 무효다.
            blocks = []
            consumed = 0
            advance(to: text)
        }
    }

    private func label(_ blockText: String) -> some View {
        BubblePlainTextLabel(
            text: blockText,
            font: font,
            textColor: textColor,
            preferredMaxLayoutWidth: width,
            lineSpacing: lineSpacing,
        )
    }

    /// 늘어난 만큼을 tail에 반영하고, 블록 길이를 넘긴 부분을 확정한다.
    ///
    /// 스트리밍 중 본문은 뒤로만 자란다(`ChatViewModel.append`). 이 전제가 깨지면 블록 경계가
    /// 어긋나는데, 완료 시점에 단일 라벨 경로로 돌아가면서 바로잡힌다.
    private func advance(to newText: String) {
        // ponytail: dropFirst는 O(consumed) 문자 순회다. 조판이 글자당 µs 단위인 데 비해
        // 여기는 ns 단위라 두 자릿수 싸고, 이게 남은 유일한 길이 비례 비용이다.
        var rest = String(newText.dropFirst(consumed))
        var settled = blocks

        while let split = MessageLineLimit.settledSplit(
            tail: rest, font: font, width: width, minLength: Self.blockLength,
        ) {
            // 블록 끝의 개행은 표시에서 빠지므로 블록 길이가 아니라 tail이 줄어든 만큼을 소비로 친다.
            consumed += rest.count - split.tail.count
            settled.append(SettledBlock(id: settled.count, text: split.block))
            rest = split.tail
        }

        blocks = settled
        tail = rest
    }
}

/// 확정된(더는 안 바뀌는) 본문 조각. `id`는 붙은 순서라 기존 블록의 뷰 정체성이 유지된다.
private struct SettledBlock: Identifiable {
    let id: Int
    let text: String
}
