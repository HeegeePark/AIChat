import SwiftUI
import UIKit

/// 응답의 첫 글자가 오기 전까지 말풍선 자리를 지키는 대기 인디케이터.
struct TypingIndicator: View {
    private static let baseDotSize: CGFloat = 7
    private static let baseSpacing: CGFloat = 5
    private static let dotCount = 3
    /// Reduce Motion On일 때 세 점 공통 불투명도(펄스·stagger 없음).
    private static let reducedMotionDotOpacity: Double = 0.6

    /// 말풍선 폭을 확정하는 쪽(`MessageBubble`)이 텍스트 대신 쓸 폭. 말풍선 높이가 본문 글꼴을 따라 커지므로
    /// 점도 같이 커져야 한다 — 안 그러면 큰 글자 설정에서 인디케이터만 쪼그라든다.
    static var width: CGFloat {
        UIFontMetrics.default.scaledValue(
            for: baseDotSize * CGFloat(dotCount) + baseSpacing * CGFloat(dotCount - 1),
        )
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAnimating = false

    private var dotSize: CGFloat {
        _ = dynamicTypeSize
        return UIFontMetrics.default.scaledValue(for: Self.baseDotSize)
    }

    var body: some View {
        HStack(spacing: UIFontMetrics.default.scaledValue(for: Self.baseSpacing)) {
            ForEach(0 ..< Self.dotCount, id: \.self) { index in
                Circle()
                    .frame(width: dotSize, height: dotSize)
                    .opacity(dotOpacity(for: index))
                    .animation(dotAnimation(for: index), value: isAnimating)
            }
        }
        // 한 줄짜리 말풍선과 같은 높이 — 첫 글자가 도착할 때 말풍선이 튀지 않는다
        .frame(width: Self.width, height: UIFont.preferredFont(forTextStyle: .body).lineHeight)
        // 접근성 레이블은 말풍선(MessageBubble)이 대기·스트리밍을 통틀어 하나로 노출한다
        .onAppear {
            // Reduce Motion On이면 반복 점멸을 시작하지 않는다.
            if !reduceMotion {
                isAnimating = true
            }
        }
    }

    private func dotOpacity(for _: Int) -> Double {
        if reduceMotion {
            return Self.reducedMotionDotOpacity
        }
        return isAnimating ? 1 : 0.25
    }

    private func dotAnimation(for index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15)
    }
}

#Preview {
    TypingIndicator()
        .padding()
        .background(Color(.secondarySystemBackground))
}
