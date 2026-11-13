# AIChat

SwiftUI로 만든 AI 채팅 앱(단일 화면)입니다. 글자 단위 스트리밍, 긴 메시지 접기, 메시지 그룹핑, 오류 유형별 재시도, 로컬 영속화를 다룹니다.
현재 응답은 Mock 서비스가 만들고, 실제 LLM 연결은 [로드맵](#로드맵)에 있습니다.

## 기술 스택

- SwiftUI (텍스트 측정·렌더 일부는 UIKit 병행) / iOS 17.0+
- Swift 6 strict concurrency
- MVVM + `@Observable` (`@MainActor` ViewModel)
- Swift Testing (단위 테스트), XCUITest (UI 테스트)
- SwiftLint, SwiftFormat (CI 린트)
- 외부 라이브러리 없이 표준 프레임워크만 사용

## 빌드 / 실행

```bash
git clone https://github.com/HeegeePark/AIChat.git
cd AIChat
open AIChat/AIChat.xcodeproj
```

> 레포 **루트**가 아니라 `AIChat/` 아래의 xcodeproj를 엽니다.

1. 툴바에서 Scheme **`AIChat`** 선택
2. 프로젝트(파란 아이콘) → **TARGETS** `AIChat` → **Signing & Capabilities** 탭
3. **Team**을 본인 계정(Personal Team)으로 변경
4. **Bundle Identifier**를 본인 것으로 변경 — 예: `com.heegeepark.AIChat` → `com.yourname.AIChat`
5. Destination에서 **iPhone 시뮬레이터** 선택 (iOS 17.0+ 런타임)
6. **⌘R**

첫 실행 시 인사말이 스트리밍으로 출력됩니다. 네트워크·API 키 설정은 필요 없습니다.

- DEBUG 수동 QA 키워드: [`docs/qa-keywords.md`](docs/qa-keywords.md)
- 테스트·린트 실행: [`docs/testing.md`](docs/testing.md)
- 문제 해결: [`docs/troubleshooting.md`](docs/troubleshooting.md)

## 프로젝트 구조

MVVM 기준으로 계층을 나눴습니다. `Models`는 순수 값 타입(`nonisolated` + `Sendable`), `ViewModels`는 `@MainActor` `@Observable` 상태 소유자, `Services`는 프로토콜(`ChatService`)로 추상화해 Mock을 주입합니다.

```text
AIChat/AIChat/
├── AIChatApp.swift              # 앱 진입점
├── Models/                      # 순수 데이터 값 타입
│   ├── Message.swift             # 메시지 모델
│   ├── Message+Samples.swift     # 프리뷰/QA용 샘플 데이터
│   ├── MessageGroup.swift        # 연속 발신자 그룹핑
│   ├── FailedRequest.swift       # 실패한 전송/스트리밍 요청
│   ├── RequestOriginals.swift    # 재시도용 원본 요청 보관
│   └── MessageFailureCopy.swift  # 오류 유형별 사용자 문구
├── ViewModels/                  # @MainActor @Observable 상태 소유자
│   ├── ChatViewModel.swift
│   └── ChatViewModel+RetryDelivery.swift  # 재시도 로직 분리
├── Views/                       # SwiftUI 화면 구성 요소
│   ├── ChatView.swift             # 최상위 화면
│   ├── MessageBubble.swift        # 말풍선
│   ├── CollapsedBubbleText.swift  # 긴 메시지 접기/펼치기
│   ├── BubblePlainTextLabel.swift # UILabel 기반 말풍선 텍스트
│   ├── StreamingBubbleText.swift  # 글자 단위 스트리밍 출력
│   ├── TypingIndicator.swift      # 타이핑 인디케이터
│   ├── MessageTimestamp.swift     # 상대시간 표시
│   ├── MessageInputView.swift     # 하단 입력창
│   ├── MessageFailureRow.swift    # 실패 상태·재시도 버튼
│   └── ScrollToBottomButton.swift # 맨 아래로 이동 버튼
├── Services/                    # 프로토콜 + Mock 구현
│   ├── ChatService.swift               # 서비스 프로토콜
│   ├── MockChatService.swift           # Mock 구현
│   ├── MockChatService+QAKeywords.swift # DEBUG QA 키워드
│   ├── UITestingChatService.swift      # UITest 전용 구현
│   └── ChatHistoryStore.swift          # 로컬 영속화
└── Utilities/                   # 순수 로직 헬퍼
    ├── RelativeTime.swift             # 상대시간 계산
    ├── TypewriterStream.swift         # 스트리밍 타이머
    ├── MessageLineLimit.swift         # 접힘 줄 수 판정
    ├── MessageLineLimit+Attributed.swift
    ├── MessageInlineMarkdown.swift    # 볼드·이탤릭·취소선 파싱
    ├── BubbleWidthBudget.swift        # 말풍선 폭 계산
    ├── ScrollBottomDetector.swift     # 최하단 스크롤 판정
    ├── ScrollViewBottomObserver.swift
    ├── LayoutScrollSignal.swift
    ├── IdleTimeoutStream.swift        # 응답 지연 timeout 감지
    ├── ChatHistoryRestore.swift       # 재실행 시 이력 복원
    └── UITestingBootstrap.swift       # UITest 부팅 훅
```

## 기능

### 메시지 전송 · 스트리밍
- [x] 하단 입력창으로 메시지를 전송하고, 입력창은 내용에 따라 **최대 3줄**까지 자동 확장된다
- [x] AI 응답이 말풍선 안에서 **글자 단위**로 순차 출력된다
- [x] 응답 대기 중 타이핑 인디케이터를 표시한다
- [x] 생성 중인 AI 응답을 사용자가 직접 중지할 수 있다

### 긴 메시지 접기 / 펼치기
- [x] 텍스트가 **5줄을 초과**하면 접힌 상태로 표시된다
- [x] 접힌 말풍선 우하단에 **「더 보기」** 버튼이 표시되고, 터치 영역은 버튼 레이블로 한정한다
- [x] 원문과 「더 보기」가 겹치지 않도록 마지막 줄을 말줄임(…) 처리한다
- [x] 「더 보기」를 탭하면 말풍선이 확장되어 원문 전체를 보여준다

### 메시지 그룹핑 · 시간 표시
- [x] 같은 발신자의 연속 메시지는 하나의 그룹으로 묶이고, 말풍선 **꼬리**는 그룹의 마지막 메시지에만 표시한다
- [x] 도착 시간을 **상대시간**(방금 전, N분 전, N시간 전 등)으로 표시하고 시간이 흐르면 자동 갱신한다

### 스크롤
- [x] 스크롤이 최하단이 아닐 때 「맨 아래로」 버튼이 나타나고, 탭하면 최하단으로 이동한다

### 오류 처리 · 재시도
- [x] timeout·네트워크·디코딩·인증·unknown 오류를 유형별로 구분해 실패 상태로 표시한다
- [x] 오류 유형에 따라 재시도 가능/불가 문구와 버튼 노출을 다르게 한다

### 로컬 영속화
- [x] 대화 이력과 말풍선 펼침 상태를 로컬에 저장하고 재실행 시 복원한다
- [x] 전송·스트리밍 도중 앱이 종료돼도 중단된 요청을 실패 상태로 복구해 재시도할 수 있다

### 접근성 · 테마
- [x] 입력창·「더 보기」·재시도 버튼에 VoiceOver 레이블과 식별자를 제공한다
- [x] Reduce Motion On 시 타이핑·스크롤 장식 애니메이션을 줄인다
- [x] Dynamic Type과 라이트/다크 모드에 자동 대응한다

### AI 응답 인라인 마크다운
- [x] 완료된 AI 응답에서 볼드·이탤릭·취소선 서식을 렌더링한다

## 설계 결정

코드 구현은 AI 에이전트가 진행했지만, 요구사항 해석·자료구조 선택·정책 경계처럼 장기 유지보수와 확장성에 걸리는 판단은 사람이 했습니다.

| 영역 | 고민 | 결정 | 근거 |
|---|---|---|---|
| 에러 정책 | 모든 오류를 "실패했어요"로 뭉뚱그리면 재시도해도 될지 사용자가 판단할 수 없음 | typed error로 오류를 구분하고 종류별로 재시도 가능 여부(`isRetryable`)와 문구를 다르게 설정. 사용자 문구와 내부 진단을 분리 | `Services/ChatService.swift`, `Models/MessageFailureCopy.swift`, `AIChatTests/ChatServiceErrorTests.swift` |
| 스트리밍 성능 | 라벨 하나로 그리면 글자마다 전체 문자열을 다시 조판해 누적 비용이 O(n²) | 틱 병합(상수 개선)·증분 높이 계산(부분 해결) 대신, 확정 블록 + tail 분리로 차수 자체를 O(n)으로 낮춤. 추측 대신 계측으로 원인을 좁힘 | `Views/StreamingBubbleText.swift`, `AIChatTests/MessageLineLimitTests.swift` |
| 목록 확장성 | 메시지가 적으면 `VStack`도 동작하지만 목록이 커지면 비용이 늘어남 | `LazyVStack` + UIScrollView offset 관찰 기반 최하단 판정을 기본 구조로 채택 | `Views/ChatView.swift`, `Utilities/ScrollViewBottomObserver.swift`, `Utilities/ScrollBottomDetector.swift` |
| 문자열 일관성 | 표시(렌더)와 측정(접힘 판정)에 서로 다른 문자열을 쓰면 접힘·말줄임이 어긋남 | 저장·표시·측정 문자열을 원문 하나로 통일 (UILabel 글자 단위 줄바꿈, 마크다운도 같은 attributed로 측정·렌더) | `Views/BubblePlainTextLabel.swift`, `Utilities/MessageLineLimit+Attributed.swift`, `Utilities/MessageInlineMarkdown.swift` |
| QA 편의성 | 접힘·timeout·실패 같은 엣지 케이스를 매번 우연에 기대 재현해야 함 | `#if DEBUG` 확장 파일로 QA 키워드를 격리해 원하는 시나리오를 즉시 강제 | `Services/MockChatService+QAKeywords.swift`, [`docs/qa-keywords.md`](docs/qa-keywords.md) |

(경로는 `AIChat/AIChat/`, `AIChat/` 기준)

## AI 도구 활용

**스펙 기반 개발**(코드보다 spec 문서가 먼저)과, **하네스(`CLAUDE.md`·`docs/gotchas.md`) 자체를 기능마다 회고로 갱신하는 루프**로 개발합니다. 파이프라인도 개선 대상이라 `ax:*` 플러그인 구조로 정리해 두었습니다.

```text
                    CLAUDE.md / ax.md / hooks         ← 항상 켜진 바닥(하네스)
                                      │
  brainstorming ──► write-specs ──► write-plans
                         │                │
                         │                ▼
                         │          execute-plans ──► XcodeBuildMCP (build/test/UI)
                         │                ▼
                         │          review-code (cold subagent)
                         │                ▼
                         │          check-quality ──► test_sim / UI 자동화
                         │                ▼
                         │          refresh-docs → retro ──► gotchas.md / CLAUDE.md 환류
                         ▼
              docs/specs · docs/plans  = 세션 간 인계 프롬프트
```

| 도구 | 역할 |
|------|------|
| **Claude Code** (`ax:*` 스킬) | spec → plan → execute → review → test → docs → retro 파이프라인 실행 |
| **`CLAUDE.md`, `.claude/ax.md`** | 매 세션 로드되는 전역 제약·경로 규약, retro로 지속 갱신 |
| **cold review subagent** | 작성 세션과 분리된 컨텍스트에서 diff만 보고 리뷰 |
| **ponytail** | 최소 diff·과도한 추상화 억제 |
| **Superset** | git worktree 기반 병렬 세션으로 여러 기능 동시 진행 |
| **XcodeBuildMCP** | build/test/UI 자동화 검증 |

프롬프트 계층·서브에이전트 역할·스킬 본문은 `.claude/ax.md`, `.claude/skills/ax/`에 코드처럼 버전 관리됩니다.

## 로드맵

- **실제 LLM 연결**: Claude·OpenAI 스트리밍 API를 외부 SDK 없이 `URLSession.bytes` SSE 파싱으로 연결, 대화 맥락 전달, Keychain 키 관리, 중지 시 요청 취소
- **블록 마크다운**: 목록·코드 블록·제목 렌더링
- **컴포넌트 패키지 분리**: 색·간격·타이포·모션 토큰과 말풍선·입력창 등 컴포넌트를 로컬 SPM 패키지로 분리, `#Preview` 카탈로그

## Reference

| 문서 | 용도 |
|------|------|
| [`docs/specs/`](docs/specs/) | 기능별 spec 문서 (새로 쌓는 중) |
| [`docs/plans/`](docs/plans/) | 기능별 plan 문서 (새로 쌓는 중) |
| [`docs/gotchas.md`](docs/gotchas.md) | 실제 밟은 함정과 대처 (증상 기반) |
| [`docs/git-workflow.md`](docs/git-workflow.md) | 브랜치·커밋·PR 규약 |
| [`docs/qa-keywords.md`](docs/qa-keywords.md) | DEBUG 수동 QA 키워드 계약·표 |
| [`docs/testing.md`](docs/testing.md) | 테스트·린트 실행 방법 |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | 빌드/실행 중 자주 겪는 증상과 확인 방법 |
| [`CLAUDE.md`](CLAUDE.md) | 에이전트 세션 전역 제약·함정 인덱스 |
| [`.claude/ax.md`](.claude/ax.md) | ax 파이프라인 경로·이슈·시뮬레이터 규약 |
| [`.claude/skills/ax/`](.claude/skills/ax/) | write-specs ~ retro 단계별 스킬, executor/reviewer/tester/docs 서브에이전트 |
