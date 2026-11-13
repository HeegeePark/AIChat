# DEBUG 수동 QA 키워드 (로컬 Run)

**DEBUG** 구성으로 실행할 때만, 입력창에 `QA:…` 토큰을 넣어 mock 응답 종류를 강제할 수 있습니다.
랜덤 프리픽스·성공 경로만으로는 보기 어려운 **장문 접힘·timeout·네트워크 실패·느린 스트리밍** 등을 재현할 때 사용합니다.

## 계약 (응답 종류 강제)

- 입력 텍스트에 **`QA:` 접두 토큰**이 있으면 `MockChatService`가 랜덤·기본 echo 대신 **고정 시나리오**로 응답한다.
- 키워드는 **메시지 앞부분 또는 단독 토큰**으로 인식한다. 예: `QA:prefix 안녕` → 프리픽스 강제 + 나머지 본문은 echo에 반영.
- **Release/Archive** 빌드에는 포함되지 않는다 (`#if DEBUG`).
- 키워드가 없으면 **기존 동작 유지** (프리픽스 랜덤, echo, 기본 TTFT).
- 실패·timeout 키워드는 **그 요청에만** 적용된다 (앱 기본 경로에 의도적 실패를 섞지 않음).
- 여러 토큰 조합 가능. 파싱 후 `QA:…` 토큰은 본문에서 제거된다. 예: `QA:slow QA:long 본문`

## 키워드 표

| 키워드 | 강제 동작 |
|--------|-----------|
| `QA:prefix` | 캐주얼 프리픽스 말풍선 1 + echo 답변 1 (항상 2스트림) |
| `QA:noprefix` | echo 답변 1개만 |
| `QA:long` | 6줄 이상(5줄 초과) 장문 — 접힘/더 보기 검증용 |
| `QA:short` | 5줄 이하 단문 (접힘 없음) |
| `QA:bold` | 완료 AI 인라인 **볼드** 픽스처 (프리픽스 끔) |
| `QA:italic` | 완료 AI 인라인 *이탤릭* 픽스처 (프리픽스 끔) |
| `QA:strike` | 완료 AI 인라인 ~~취소선~~ 픽스처 (프리픽스 끔) |
| `QA:timeout` | 첫 청크 전 idle timeout (빈 실패) |
| `QA:partial-timeout` | 일부 글자 후 hang → 부분 수신 timeout |
| `QA:network` | `ChatServiceError.network` |
| `QA:decoding` | `ChatServiceError.decoding` (재시도 불가) |
| `QA:unauthorized` | `ChatServiceError.unauthorized` (재시도 불가) |
| `QA:unknown` | `ChatServiceError.unknown` |
| `QA:empty` | throw 없이 빈 스트림 종료 → 빈 실패 UI |
| `QA:slow` | 청크/글자 지연 증가. 다른 본문 키워드가 없으면 `QA:long`과 동일한 6줄 이상 장문으로 대체 — 스트리밍·인디케이터 관찰용 |

## 사용 방법

1. **의도적 재현 (권장):** 입력창에 위 키워드를 넣고 전송.
2. **일반 관찰:** 키워드 없이 여러 번 보내 랜덤 프리픽스·청크 길이를 확인.
3. 구현: `MockChatService+QAKeywords.swift` (`#if DEBUG`) · 단위 테스트: `MockChatServiceQAKeywordTests.swift`
   제거 시: 위 파일 + `MockChatServiceQAKeywordTests.swift` + `send`의 `#if DEBUG` 블록.
