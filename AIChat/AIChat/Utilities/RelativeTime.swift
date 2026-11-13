import Foundation

/// 메시지 도착 시각을 상대시간 문자열로 바꾼다.
///
/// 1분 이상은 `RelativeDateTimeFormatter`에 맡긴다 — 달력 단위(월 길이·윤년)를 직접 계산할 이유가 없다.
/// `.numeric`을 쓰는 건 `.named`가 "어제"·"지난주"·"작년" 같은 대명사로 치환해 숫자 표기를 지워버리기 때문.
nonisolated enum RelativeTime {
    /// 60초 미만은 포맷터에 맡기지 않는다. 갱신 주기가 60초라 "30초 전" 같은 값이 1분 내내 굳어
    /// 실제 경과와 어긋나고, 0초에는 미래형("0초 후")이 나온다. 미래 시각(음수 경과)도 이 분기가 받는다.
    static func string(from date: Date, to now: Date = .now) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "방금 전" }

        // 포맷터를 static let으로 캐시하지 않는다 — non-Sendable 클래스라 nonisolated 타입의 전역
        // 상수로 두려면 격리를 명시해야 하고, 그러면 이 함수와 테스트까지 격리가 번진다.
        // 호출은 화면에 보이는 말풍선당 1분에 한 번이라 생성 비용이 문제 되지 않는다.
        let formatter = RelativeDateTimeFormatter()
        // .named는 "어제"·"지난주"·"작년" 같은 대명사로 치환해 숫자 표기를 지운다.
        // (unitsStyle은 기본값이 .full이라 따로 지정하지 않는다 — 실측 확인)
        formatter.dateTimeStyle = .numeric
        // 앱 전체 UI 문자열이 한국어 리터럴이라(String Catalog 미도입) 여기만 기기 로케일을 따르면
        // "방금 전"과 "5 minutes ago"가 한 화면에 섞인다. 게다가 knownRegions에 ko가 없어
        // 로케일을 풀면 한국어 기기에서도 영어로 떨어질 수 있다.
        // 다국어를 지원하게 되면 이 고정을 String Catalog 이관과 함께 걷어낸다.
        formatter.locale = Locale(identifier: "ko_KR")

        return formatter.localizedString(for: date, relativeTo: now)
    }
}
