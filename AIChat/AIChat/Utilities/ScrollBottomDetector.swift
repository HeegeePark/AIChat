import CoreGraphics

nonisolated enum ScrollBottomDetector {
    /// content 하단까지 남은 스크롤 거리가 `tolerance` 이하면 최하단.
    ///
    /// UIKit 최하단 근처: `contentOffset.y ≈ contentHeight - viewportHeight + adjustedContentInset.bottom`.
    /// 남은 거리:
    /// `distanceFromBottom = contentHeight - (contentOffsetY + viewportHeight)
    ///     + adjustedContentInsetBottom - trailingSlack`
    /// `isAtBottom = distanceFromBottom <= tolerance`
    ///
    /// `trailingSlack`: 메시지 목록 **뒤**에 붙인 스크롤 여백(예: 전송 후 `anchor: .top`용
    /// 뷰포트 높이 `Color.clear` 스페이서). contentSize에는 포함되지만 “대화 최하단” 판정에서는
    /// 제외해야 한다. 0이면 content 절대 끝을 기준으로 한다.
    ///
    /// Edge cases (의도적으로 true — 하단 이동 버튼 깜빡임 방지 / 스크롤 불필요 구간):
    /// - `viewportHeight <= 0` 또는 `contentHeight <= 0`: 레이아웃 미준비 → **true**
    /// - 메시지 영역(`contentHeight - trailingSlack`)이 뷰포트 이하면 스크롤 불필요 → **true**
    static func isAtBottom(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        adjustedContentInsetBottom: CGFloat = 0,
        trailingSlack: CGFloat = 0,
        tolerance: CGFloat = 20,
    ) -> Bool {
        // Layout not ready: prefer hide "scroll to bottom" button (treat as at bottom).
        if viewportHeight <= 0 || contentHeight <= 0 {
            return true
        }
        let slack = max(0, trailingSlack)
        // Message region (excluding trailing spacer) fully fits; no scroll needed.
        if contentHeight - slack <= viewportHeight {
            return true
        }
        // Add bottom inset (do not subtract): max offset grows with inset, so remaining
        // distance at true bottom is ~0 only when inset is added back.
        let distanceFromBottom =
            contentHeight
                - (contentOffsetY + viewportHeight)
                + adjustedContentInsetBottom
                - slack
        return distanceFromBottom <= tolerance
    }
}
