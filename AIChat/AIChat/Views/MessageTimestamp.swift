import SwiftUI

/// 말풍선 옆에 붙는 상대시간 캡션. 스스로 1분마다 갱신된다.
struct MessageTimestamp: View {
    let date: Date

    var body: some View {
        // 기준을 `.now`가 아니라 메시지 시각으로 잡는다 — 표기가 바뀌는 순간이 전부 메시지 시각의
        // 60초 배수라, `.now` 기준이면 위상이 어긋나 전환이 최대 59초 늦게 반영된다.
        // 셀마다 Timer를 돌리지 않고 TimelineView에 맡겨야 취소·백그라운드 복귀를 시스템이 처리한다.
        TimelineView(.periodic(from: date, by: 60)) { context in
            Text(RelativeTime.string(from: date, to: context.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                // VoiceOver에는 상대시간보다 절대시간이 유용하다("3분 전"은 읽는 시점에 이미 어긋난다).
                .accessibilityLabel(date.formatted(date: .abbreviated, time: .shortened))
        }
        // 캡션이 좁은 잔여 폭에서 두 줄로 접히지 않게 이상적 폭을 확보한다.
        .fixedSize()
    }
}
