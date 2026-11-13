import SwiftUI

/// 실패 말풍선 아래 행: 유형별 부분 수신 안내 + 재시도 버튼, 또는 재시도 불가 정적 안내.
/// ChatView 본문에서 분리해 실패 UI 분기만 이 뷰가 소유한다.
struct MessageFailureRow: View {
    let message: Message
    /// ViewModel `failedRequests` 멤버십. 유형 정책(`MessageFailureCopy.isRetryable`)과 분리한다.
    let canRetry: Bool
    let leadingInset: CGFloat
    let onRetry: () -> Void

    var body: some View {
        // 큰 글자 설정에선 한 줄에 둘 다 못 들어가 각각 접혀 읽기 어려워진다 — 그때만 세로로 떨어뜨린다.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                failureCaption
                trailingControl
            }
            VStack(alignment: .leading, spacing: 4) {
                failureCaption
                trailingControl
            }
        }
        .font(.footnote)
        // 아바타 칸만큼 들여써 말풍선 왼쪽 끝과 맞춘다
        .padding(.leading, leadingInset)
    }

    /// 부분 수신일 때만 유형별 부가 안내. 빈 실패 본문과 문구가 겹치지 않게 한다.
    @ViewBuilder
    private var failureCaption: some View {
        if !message.text.isEmpty {
            Text(MessageFailureCopy.partialFailureCaption(
                for: MessageFailureCopy.resolvedFailure(for: message),
            ))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        // 버튼은 재요청 원본이 있을 때만 — 유형만 보고 켜면 고아 `.failed`에서 죽은 컨트롤이 된다.
        if canRetry {
            // Label의 심볼은 글꼴 배율을 따라가므로 고정 pt 도형과 달리 Dynamic Type에서 같이 커진다.
            // 레이블만으로는 히트 영역이 글자 높이(~18pt)라 HIG 최소치에 못 미쳐 44pt를 따로 확보한다.
            Button(action: onRetry) {
                Label("다시 시도", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("다시 시도")
            .accessibilityIdentifier("retryButton")
        } else if !MessageFailureCopy.isRetryable(for: message) {
            // 정책상 재시도 불가 — 버튼 자리 대신 인지 문구.
            Text(MessageFailureCopy.nonRetryableNotice)
                .foregroundStyle(.secondary)
                .accessibilityLabel(MessageFailureCopy.nonRetryableNotice)
        }
        // 유형은 retryable인데 원본이 없는 고아 실패: 버튼·불가 문구 모두 없이 말풍선만 남긴다.
    }
}
