import Foundation

extension Message {
    /// 말풍선 개행·폭 검증용 장문 픽스처.
    /// #Preview와 접기/더보기 검증에서 재사용.
    nonisolated static let longTextSamples: [Message] = {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func ts(_ offset: TimeInterval) -> Date {
            base.addingTimeInterval(offset)
        }

        return [
            // 1. 한글 장문 — 어절 중간 줄바꿈(글자 단위) vs 어절 경계만 여부 판정
            Message(
                sender: .ai,
                text: """
                안녕하세요. 오늘은 말풍선 안에서 긴 한글 문장이 어떻게 줄바꿈되는지 확인하려고 \
                어절 길이를 들쭉날쭉하게 섞어 썼습니다. 짧은 말 옆에는 상당히 긴 어절을 붙여 두고, \
                조사와 접속사를 사이사이에 넣어 문장 흐름은 자연스럽되 줄 끝 여백이 어디서 생기는지 \
                눈에 띄게 만들었습니다. 예를 들면 사용자인터페이스구성요소라든가 \
                비동기스트림처리방식 같은 긴 표현 바로 뒤에 아주 짧은 단어를 두면 줄이 어디서 \
                갈라지는지 비교하기 쉽습니다. 이 문단은 다섯 줄을 분명히 넘기도록 충분히 길게 \
                이어지며, 같은 단어를 기계적으로 반복하지 않아 줄바꿈 위치 차이가 가려지지 않게 했습니다.
                """,
                timestamp: ts(0),
                status: .completed,
            ),
            // 2. 영문 장문 — 일반 단어(substantially)도 글자 단위로 잘려 줄 끝 여백을 메우는지
            Message(
                sender: .ai,
                text: """
                Hello. This paragraph deliberately mixes short tokens with substantially longer \
                vocabulary so asdgasdg and other runs stay dense: configuration, asynchronous, \
                interoperability, thumbnail, cache, queue. When a long Latin word cannot fit the \
                remaining width it should break mid-token instead of leaving a large trailing gap. \
                We keep adding varied clauses about networking timeouts, retry policies, and layout \
                measurement so the bubble clearly exceeds five lines without repeating only short words.
                """,
                timestamp: ts(1),
                status: .completed,
            ),
            // 3. 한글+영문 혼용 — 영문 토큰이 통째로 밀리며 한글 줄 끝에 여백을 만드는지
            Message(
                sender: .user,
                text: """
                방금 확인한 API 응답에서 content-type이 application/json 이었고, \
                retryAfter 헤더는 120초로 잡혀 있었습니다. 클라이언트 쪽에서는 URLSession의 \
                timeoutIntervalForRequest를 조정한 뒤 ExponentialBackoff 전략을 적용해 보려 하는데, \
                한글 설명과 English identifiers가 한 문단에 섞이면 줄 끝 여백이 어떻게 생기는지 \
                보고 싶습니다. 특히 ConfigurationManager 같은 긴 심볼 다음에 짧은 한글 조사가 \
                붙는 패턴이 실제 채팅에서 자주 나와서, 그 경계에서 말풍선이 듬성듬성해 보이지 않는지 \
                픽셀 단위로 확인하려고 이 문장을 일부러 길게 적었습니다.
                """,
                timestamp: ts(2),
                status: .completed,
            ),
            // 4. 이모지 섞인 장문 — lineHeight 대비 글리프 높이 차이로 줄 수 추정 오차 확인
            Message(
                sender: .user,
                text: """
                오늘 데모 준비하면서 체크리스트를 정리했어요 📝 우선 로그인 흐름 ✅ 그다음 \
                메시지 전송 ⚡ 스트리밍 응답 🌊 그리고 말풍선 레이아웃 🎨 까지 순서대로 봤습니다. \
                이모지가 문장 중간에 끼면 줄 높이 계산이 흔들릴 수 있어서, 짧은 단어 🌸 긴 설명 \
                사이사이에 다양한 이모지를 넣었습니다 🚀📱💬. 이 문단도 다섯 줄 넘게 이어지도록 \
                배경 설명과 기대 결과를 덧붙였고, 마지막에는 수고했다는 인사를 남겨 둡니다 🙌 \
                스크린샷에서 줄 수 접힘 판정이 안전 쪽으로 기울는지만 보면 됩니다.
                """,
                timestamp: ts(3),
                status: .completed,
            ),
            // 5. URL 포함 장문 — 줄바꿈 불가 토큰이 통째로 다음 줄로 밀리는 케이스
            Message(
                sender: .ai,
                text: """
                참고 문서는 https://developer.apple.com/documentation/swiftui/text 와 \
                https://developer.apple.com/documentation/uikit/nsstringdrawing 를 보면 됩니다. \
                긴 URL이 현재 줄에 들어가지 않으면 통째로 다음 줄로 내려가면서 오른쪽에 빈 구간이 \
                크게 보일 수 있습니다. 추가로 내부 위키 링크 https://example.com/wiki/bubble-layout-notes \
                도 같은 패턴입니다. 이 메시지는 URL 주변 한글 설명을 충분히 늘려 다섯 줄을 넘기고, \
                폭 제한 이후에도 말풍선 밖으로 URL이 넘치지 않는지 확인하는 용도입니다.
                """,
                timestamp: ts(4),
                status: .completed,
            ),
            // 6. 공백 없는 초장문 단어 — 최대 폭보다 긴 단일 토큰 분해/넘침
            Message(
                sender: .user,
                text: """
                아래는 의도적으로 공백 없는 초장문 토큰입니다. \
                가나다라마바사아자차카타파하ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\
                가나다라마바사아자차카타파하\
                VeryLongUnbrokenTokenWithoutAnyWhitespaceForBubbleOverflowCheck\
                가나다라마바사아자차카타파하. \
                이 토큰 앞뒤로 짧은 설명을 두어 말풍선이 전체적으로 다섯 줄을 넘기게 했고, \
                토큰이 밖으로 넘치는지 글자 단위로 강제 분해되는지를 관찰합니다.
                """,
                timestamp: ts(5),
                status: .completed,
            ),
            // 7. 마크다운 혼재 장문 — AI completed는 인라인 3종만 서식, 코드·목록 마커는 리터럴
            Message(
                sender: .ai,
                text: """
                **굵게** 표시와 `코드` 조각, - 목록 기호가 섞인 예시입니다. \
                완료 AI 말풍선에서는 볼드만 서식으로 보이고 백틱·목록 기호는 그대로 남을 수 있습니다. \
                측정과 렌더는 같은 파싱 결과(표시 plain + 런)를 씁니다. \
                - 첫 번째 항목은 레이아웃 폭 \
                - 두 번째 항목은 줄바꿈 규칙 \
                - 세 번째 항목은 접힘 판정 \
                위 목록 형태 문자열을 포함해 문단을 길게 이어 다섯 줄을 넘깁니다.
                """,
                timestamp: ts(6),
                status: .completed,
            ),
            // 8. #으로 시작하는 한글 장문 — 헤딩처럼 보여도 verbatim + 줄바꿈 어색함 확인
            Message(
                sender: .user,
                text: """
                # 개행 제어 점검 메모 \
                이 문장은 해시로 시작하지만 마크다운 헤딩으로 렌더되면 안 됩니다. \
                제목처럼 보이는 문자열 뒤에도 본문 설명을 충분히 붙여 다섯 줄을 넘기고, \
                문장부호·공백 근처에서 줄이 어색하게 갈라지지 않는지 봅니다. \
                해시 바로 다음 공백과 이어지는 한글 어절의 경계가 특히 중요하며, \
                전체 말풍선 밀도는 다른 한글 장문 케이스와 같은 기준으로 비교합니다.
                """,
                timestamp: ts(7),
                status: .completed,
            ),
            // 9. 개행문자 포함 장문 — 명시적 \n + 폭 제한·줄 수 추정
            Message(
                sender: .ai,
                text: """
                첫 번째 단락입니다. 사용자가 입력창에서 직접 줄을 바꾼 상황을 흉내 냅니다.

                두 번째 단락은 조금 더 길게 써서, 명시적 개행 이후에도 자동 줄바꿈이 \
                폭 제한 안에서 이어지는지 확인합니다. 세 번째 줄로 넘어가기 전에 \
                어절 길이를 다양하게 섞고, 마지막까지 설명을 이어 다섯 줄 이상이 되게 합니다.
                """,
                timestamp: ts(8),
                status: .completed,
            ),
            // 10. 짧은 메시지 — 최대 폭이 상한이지 고정 폭이 아님을 확인하는 대조군
            Message(
                sender: .user,
                text: "네",
                timestamp: ts(9),
                status: .completed,
            ),
        ]
    }()

    /// 인라인 마크다운(볼드·이탤릭·취소선) 육안 확인용.
    /// AI completed만 서식 적용. 사용자 샘플은 마커가 그대로 남아야 한다.
    /// `MessageBubble` `#Preview("Inline Markdown")` 및 Task 7 시각 검증에서 재사용.
    nonisolated static let inlineMarkdownSamples: [Message] = {
        let base = Date(timeIntervalSince1970: 1_700_000_100)
        func ts(_ offset: TimeInterval) -> Date {
            base.addingTimeInterval(offset)
        }

        return [
            Message(
                sender: .ai,
                text: "이 문장에 **굵은 강조**가 포함됩니다.",
                timestamp: ts(0),
                status: .completed,
            ),
            Message(
                sender: .ai,
                text: "이 문장에 *기울임 강조*가 포함됩니다.",
                timestamp: ts(1),
                status: .completed,
            ),
            Message(
                sender: .ai,
                text: "이 문장에 ~~취소선 강조~~가 포함됩니다.",
                timestamp: ts(2),
                status: .completed,
            ),
            // 접힘 + 서식: collapsedLines를 넘는 길이, 단일 볼드 구간
            Message(
                sender: .ai,
                text: """
                접힘 검증용 장문입니다. 아래 **핵심 문장**만 굵게 보여야 합니다. \
                이어지는 설명은 서식 없이 plain으로 충분히 길어 말풍선이 접히고 \
                마지막 줄에 말줄임과 더 보기 버튼이 나타나게 합니다. \
                줄 수 판정은 파싱 후 표시 문자열과 런 속성을 기준으로 하므로, \
                마커 포함 원문으로 잰 결과와 접힘 경계가 다를 수 있습니다. \
                펼친 뒤에도 **핵심 문장** 서식이 유지되는지 확인합니다.
                """,
                timestamp: ts(3),
                status: .completed,
            ),
            // 대조: 사용자 메시지는 마크다운 미적용
            Message(
                sender: .user,
                text: "사용자는 **별표**가 그대로 보여야 합니다.",
                timestamp: ts(4),
                status: .completed,
            ),
        ]
    }()
}
