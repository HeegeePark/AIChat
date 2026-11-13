import CoreGraphics

/// 발신자별 말풍선 텍스트 상한 폭. AI 행만 아바타 열을 예산에서 빼고, user 행은 가용 content 폭 기준.
nonisolated enum BubbleWidthBudget {
    /// - Parameters:
    ///   - containerWidth: `GeometryReader`가 잰 ScrollView 쪽 폭(패딩 전).
    ///   - stackHorizontalPadding: 리스트 VStack 좌우 padding 합.
    ///   - avatarColumn: 아바타 지름 + 행 spacing (AI 예산에서만 차감).
    ///   - ratio: 가용 폭에 곱하는 말풍선 최대 비율.
    static func maxBubbleWidth(
        for sender: Message.Sender,
        containerWidth: CGFloat,
        stackHorizontalPadding: CGFloat,
        avatarColumn: CGFloat,
        ratio: CGFloat,
    ) -> CGFloat {
        guard containerWidth > 0, ratio > 0 else { return 0 }

        let contentWidth = containerWidth - stackHorizontalPadding
        guard contentWidth > 0 else { return 0 }

        switch sender {
        case .user:
            return contentWidth * ratio
        case .ai:
            let available = contentWidth - avatarColumn
            guard available > 0 else { return 0 }
            return available * ratio
        }
    }
}
