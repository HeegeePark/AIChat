# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트
SwiftUI AI 채팅 앱 (단일 화면). 채팅 UI 컴포넌트와 LLM 스트리밍 연동을 다룬다.

## 툴체인/타깃 (엄수)
- 배포 타깃: iOS 17.0 (iOS 17에서 동작하는 API만 사용, 상위 버전 전용 API 금지)
- 툴체인: Xcode 26 / Swift 6.3 (기본 툴체인)
- 언어 모드: Swift 6 strict concurrency. `@Observable` ViewModel은 `@MainActor`로 격리, `AsyncStream` 소비 등 비동기 상태 업데이트는 MainActor 안에서 수행
- 외부 라이브러리 절대 금지 (표준 프레임워크만). 텍스트 줄 수 측정 등 필요 시 UIKit(TextKit/CoreText) 병행 허용

## 아키텍처
- MVVM + `@Observable` (iOS 17 Observation, `ObservableObject` 아님)
- `@State`는 로컬 뷰 상태에만, 화면 상태는 ViewModel이 소유
- 서비스는 프로토콜로 추상화 + Mock 주입 (실서버 교체 가능하게)
- 뷰 100줄 초과 시 하위 뷰로 추출
- 비동기: async/await, AsyncStream 우선
- 값 타입 우선, 강제 언래핑 금지
- 프로젝트 빌드 설정이 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`라 모듈 내 타입은 기본적으로 `@MainActor`로 격리된다. Model 등 순수 데이터 값 타입은 `nonisolated` + `Sendable`을 명시해 액터 경계를 자유롭게 넘나들 수 있게 한다 (`@MainActor` 격리는 ViewModel처럼 상태를 소유하는 타입에만 건다)

## 폴더 구조
`AIChat/AIChat/`(Xcode 타깃 소스 루트) 아래 `App/` `Models/` `ViewModels/` `Views/` `Services/` `Utilities/`
- 프로젝트는 Xcode 16+ file system synchronized group을 쓴다(`AIChat.xcodeproj/project.pbxproj`에 `objectVersion = 77`, `PBXFileSystemSynchronizedRootGroup` 존재). `AIChat/AIChat/` 하위에 폴더/파일을 새로 만들거나 지워도 자동으로 타깃에 반영되므로, 이 트리 안에서의 파일 추가·삭제는 `.pbxproj` 수동 편집이 필요 없다(엄격히 금지되는 건 프로젝트 설정 변경 자체지, 이 트리 안 파일 추가/삭제가 아님).

## 빌드/검증 (XcodeBuildMCP 사용)
- 빌드: `mcp__XcodeBuildMCP__build_sim` (빌드+실행은 `build_run_sim`) / 테스트: `test_sim`
- 실행+스크린샷: `boot_sim` → `install_app_sim` → `launch_app_sim` → `screenshot`
- UI를 바꾸면 반드시 스크린샷으로 결과를 확인한다 (확대 검증 방법은 아래 함정 사전 「화면 검증」)
- MCP를 못 쓰는 상황에서만 bash로 폴백: `xcodebuild ... | xcbeautify --quiet`
- 세션 기본 시뮬레이터는 첫 `build_sim` 호출 **전에** `list_sims` 결과의 `runtime` 필드부터 확인하고 고른다. `.claude/settings.json`의 `DEFAULT_SIMULATOR`(iPhone 16) 이름을 실제 런타임 확인 없이 그대로 `session_set_defaults`에 넘기면 안 된다 — 이 머신에서 `iPhone 16`은 이 Xcode가 지원하지 않는 구 런타임(iOS 18.6)에 묶여 있고 `iPhone 17`류가 최신 런타임(iOS 26.5)이므로 최신 런타임 기기를 고른다.
- 여러 워크트리(병렬 세션)에서 동시에 작업하면 같은 번들 ID를 나중에 install/launch한 세션이 앞선 세션의 빌드를 덮어쓴다 — 워크트리마다 `list_sims`에서 서로 다른 UDID를 골라 `session_set_defaults`로 `simulatorId`를 고정한다. **이미 `state: Booted`인 기기는 다른 세션이 이미 쓰고 있을 가능성이 높다**(실제로 다른 워크트리 세션이 남긴 테스트 데이터가 들어있던 사례 있음) — Booted 기기를 재사용하지 말고, 최신 런타임의 `Shutdown` 기기를 새로 `boot_sim`해 독점 사용한다.

## 함정 사전 (`docs/gotchas.md` — 해당 작업 전에 그 절만 읽는다)
매 세션 통째로 읽지 않는다. 아래 증상/작업에 걸리면 그때 해당 절을 `Read`한다. 새로 얻은 교훈도 이 문서의 해당 절에 추가한다.

- 텍스트 줄바꿈·줄 수 측정·말줄임·말풍선 폭을 건드림 / 스트리밍처럼 글자가 계속 붙는 텍스트가 **길어질수록 점점 느려짐**(O(n²) 시그니처) / 스트리밍 중 CPU가 100% 근처로 붙음 / 라벨을 여러 개로 쪼개 쌓았더니 줄 간격·높이가 어긋남 / 렌더는 바꿨는데 접힘만 어긋남(하이브리드 측정) / ZWSP·표시 변환 우회를 테스트로만 봉인하려 함 / UILabel 말풍선 Expand UITest가 개행 장문 원문을 못 찾음 / 줄바꿈 정본이 바뀌었는데 이슈 본문이 옛 수단(ZWSP 등)을 가리킴 / 옛 조사 절 파이프라인을 후속 스펙에 복붙했다가 폐기 경로(ZWSP 등)를 다시 설계함 / 접힌 사용자 말풍선에서 말줄임(`…`)만 검게 보임(본문은 흰데) / AI 응답 `**bold**` 표시만 바꾸고 접힘이 어긋남 / 스트리밍 중 마크다운 깜빡임·CPU 폭주 / `LocalizedStringKey`로 AI 문자열을 넘겼더니 `%`가 깨짐 / 한글 이탤릭이 안 보이거나 영문만 기울어 보임 / 파서 단위 테스트는 그린인데 뷰에서 AI 완료에만 적용하는 게이트가 빠져 있음 → 「텍스트 조판 · 줄 수 · 말줄임」
- 스크롤 위치가 안 잡힘 / 키보드가 뜰 때 레이아웃이 밀림 / `Spacer` 앵커링 정렬이 어긋남 / `HStack` 안에서 텍스트가 절반에서 잘림 / 큰 글자 설정에서 곁들임 요소(캡션·배지)가 화면 밖으로 잘림 — 특히 `AX-*`는 멀쩡한데 `xxxLarge`에서만 / `ViewThatFits`가 넘치는데도 첫 후보를 고름 / `.bottom` 정렬 행에서 말풍선 아래에 뭘 붙였더니 아바타가 같이 내려감 / 뷰가 100줄을 넘는데 초과분이 하위 뷰로 뽑기 애매한 순수 스타일 계산임 / `LazyVStack` 안에서 스크롤 가시성(최하단 여부 등)이 `GeometryReader`+`PreferenceKey`로 안 잡힘 / 맨 아래 버튼이 최하단·런치 직후에도 남음(trailingSlack·inset 부호·전송 스페이서 위치) / Lazy 복구 시 Preference 마커를 다시 넣으려 함 / `GeometryReader` 파생 상태가 런치 시 잠깐 깜빡임 / 리스트 원소 하나가 자주 바뀔 때 "전체가 다시 그려진다"고 보고 성능 대책을 세우려 함 / 뷰 값이 안 바뀌었는데도 자식 body·`UIViewRepresentable`이 계속 갱신됨(클로저 저장 프로퍼티) / `intrinsicContentSize`·`sizeThatFits`가 갱신당 여러 번 돎 / 스트리밍처럼 콘텐츠가 계속 자라는 동안 스크롤을 하단에 자동 고정할지 판단해야 함 / 최하단에서 더 스크롤하면 빈 화면이 나옴(전송용 스페이서가 상시 켜져 있음) / `ChatView`에 상태·코드를 몇 줄만 추가했는데 커밋 전 `swiftlint --strict`가 `type_body_length`로 새로 실패함 → 「SwiftUI 레이아웃」
- VoiceOver로 `Button` 등 컨트롤이 안 눌림 / 접근성 요소 여러 개가 하나의 읽기 전용 텍스트로 뭉쳐 읽힘 / 대기·로딩 같은 **과도 상태를 화면에 새로 노출**함(사라질 때 VoiceOver 포커스가 튀고, 고정 pt 도형은 Dynamic Type에서 안 커진다) / 입력 TextField가 identifier만 있어 목적이 안 읽힘 / 빈 실패 말풍선이 완료 답변과 VO에서 안 구분됨 / Reduce Motion을 “애니 전부 삭제”로 오해함 / Preview에 `accessibilityReduceMotion` 주입이 빌드 에러 → 「SwiftUI 접근성」
- `init` 기본 파라미터에 mock·`static let`을 넣었더니 actor isolation 에러 / `nonisolated struct`인데 "main actor-isolated instance method ... cannot be called from outside of the actor"가 **일부 호출부에서만** 남 / 포맷터 같은 non-Sendable 객체를 `static let`으로 캐시했더니 격리가 테스트까지 번짐 / `@MainActor` `@Observable` deinit에서 Task cancel이 isolation 에러 / UIScrollView KVO 콜백에서 MainActor 메서드를 직접 부르면 경고·플링 중 `Task { @MainActor }` 폭주 → 「Swift 동시성」
- 디바운스·취소가 있는 async 흐름을 만짐 / `Task`를 취소했는데 `AsyncStream` 프로듀서가 안 멈춤·`onTermination`이 안 불림 / 표준 라이브러리 동시성 의미론이 예상과 달라 격리 확인이 필요함 / 부분 수신 후 스트림 에러인데 말풍선 마지막 글자가 빠짐 / 동시 재시도 테스트가 스트리밍 전에 통과해 버림(`contains("A")`가 유저 말풍선에 매칭) / ViewModel이 보관한 `Task { self… }` 때문에 해제·deinit cancel이 안 됨 / hang mock이 greeting·send를 같이 막아 레이스 테스트가 안 끝남 / 부분 스트리밍 단언이 TypewriterStream 보류 글자 때문에 빗나감 → 「비동기 · 디바운스」
- 빌드가 `SUCCEEDED`인데 새 타입을 못 찾음 / 에디터가 "Cannot find type in scope"·"No such module" 표시 / 빌드·테스트가 `manifest.json`을 못 쓰고 "No space left on device"로 죽음 / `test_sim`이 `Unable to Install … isn't enough storage`·`XCTestDevices` ENOSPC로 죽음 / Bash 호출이 전부 `ENOSPC ... tasks/*.output`으로 실패함(`!` 명령 포함) → 「빌드 캐시 · SourceKit 진단」
- 시뮬레이터에 텍스트를 입력해야 함(영문이어도 해당 — `type_text`는 호스트 macOS 입력기 상태에 따라 깨질 수 있다. **항상** `type_text` 말고 페이스트보드 경로를 기본으로 쓴다) / 붙여넣은 내용이 방금 `pbcopy`한 것과 다름 / `snapshot_ui`가 응답 없음 / 탭이 안 먹힘 / `long_press`로 Paste 콜아웃이 안 뜸 / 소프트웨어 키보드가 안 뜸(미해결 제약, 우회책만 있음) / `swipe`해도 스크롤이 안 됨 / `install_app_sim`·`build_run_sim`이 Mach error로 실패 / 잘 쓰던 기기에 `simctl` 명령이 갑자기 `Unable to lookup in current state: Shutdown`으로 무더기 실패(디스크 여유 낮을 때 반복될 수 있음) → 「시뮬레이터 자동화」
- 스크린샷으로 몇 pt 차이를 판정해야 함 / 다크모드·Dynamic Type 확인 / Reduce Motion On/Off를 시뮬에서 강제로 켜야 함 / 레이아웃 계산값이 예상과 다름 / 조건부 UI를 다크모드·Dynamic Type에서 강제로 띄워 확인해야 함 / 몇 초 만에 지나가는 과도 상태(스트리밍·애니메이션 중간)를 스크린샷으로 못 잡음 → 「화면 검증 (스크린샷 · 런타임 값)」
- `test_sim` 전체 실행에서만 타이밍 테스트가 간헐 실패함 / 테스트 결과에 `DTDKRemoteDeviceConnection`·"device is passcode protected" 에러가 잔뜩 남 / 테스트 코드를 고친 뒤 `build_sim`만 보고 통과로 판정하려 함 / 임시 코드를 되돌리는 스크립트가 대상 문자열을 못 찾음 / 검증용 `grep`이 0건인데 실제로는 존재함 / 단위만 통과하는데 표준 전체 Test 액션이 실패함(UITests 소스 비어 있음) / XCUITest가 `messageInput`을 못 찾거나 보낸 말풍선 원문 텍스트를 못 찾음 / UILabel 말풍선에서 개행 포함 전체 본문 `staticTexts` 조회가 실패함 / accessibilityIdentifier만 넣었는데 단위 테스트를 어떻게 짜야 할지 막힘 / `moreButton` 탭이 "Multiple matching elements"로 실패 / 펼침 후 마지막 줄 토큰만 찾으면 실패 / timeout UI를 실제 10초 대기로 재현하려 함 / 단위 테스트 double을 UITest에서 쓰려 함 → 「테스트 실행 · 플레이크」
- 자동 빌드·테스트·스크린샷은 다 통과하는데 휴먼 QA가 실기기에서 성능 문제를 잡아옴 / 성능 수정의 전후를 무엇으로 재야 할지 모르겠음 / `ps %cpu`로 잰 CPU가 시간이 갈수록 낮아져 부하가 끝난 것처럼 보임 / 성능 계측 하네스를 어떻게 붙이고 지울지 / 성능 이슈에 무엇까지 적어야 할지 → 「성능 회귀 · 자동 검증의 사각」
- `.mcp.json`을 고쳤는데 도구가 안 잡힘 → 「MCP 설정」
- 로컬 저장(UserDefaults/Codable) 도입, SwiftData 채택 여부 판단, 재실행 후 상태 복원을 시뮬레이터로 검증 / 진행 중·대기 상태를 새로 추가했는데 그게 저장 경로에 실릴 수 있음 / 앱 데이터를 지웠는데 이전 대화가 그대로 복원돼 새 동작이 아예 안 탐 / "더 보기"를 탭한 뒤 재실행해도 접힌 말풍선·`moreButton`이 안 돌아와 Dynamic Type 등 접힘 검증을 못 함 / "다시 시도" 버튼이 보이는데 눌러도 아무 일도 없음 / 저장 스키마에 필드를 추가했는데 옛 이력이 통째로 안 읽힘 / 스트리밍 중 앱을 죽였더니 부분 글자가 디스크에 없음 / 복원 정규화는 됐는데 재실행할 때마다 같은 스냅샷이 다시 깨져 보임 / 동시 "다시 시도" 후 한쪽만 복원 재시도가 죽음 → 「로컬 영속화」

## 작업 규칙
- 코드 수정 후 빌드 통과를 확인한 뒤 다음 단계로
- 한 번에 한 기능씩, 기능 단위로 커밋
- 정답이 갈리는 판단(예: 줄 수 측정 방식)은 임의 결정 말고 선택지를 제시해 확인받는다
- 원인을 추측으로 단정하지 않는다 — 서드파티 도구/의존성이 실패하면 더 낮은 레벨(바이너리 직접 실행 등)로, 레이아웃·계산값이 이상하면 런타임 로그로 격리해 확인한 뒤 전달한다
- **성능은 테스트 통과로 말하지 않는다** — 이 프로젝트의 자동 검증은 성능 회귀를 구조적으로 못 잡는다(P0 성능 회귀가 전 구간 그린인 채 휴먼 QA에 걸렸다). 이유와 계측법은 함정 사전 「성능 회귀 · 자동 검증의 사각」

## 금지
- 외부 라이브러리, iOS 17 미지원 API, 강제 언래핑(테스트에서 옵셔널 언래핑이 필요하면 `try #require(...)` 사용), 100줄 넘는 모놀리식 뷰
- 요구사항에 없는 기능의 임의 확장 (개선은 필수 기능 완성 후)

## Git 워크플로우
브랜치 네이밍·충돌 해결·커밋 예시 등 자세한 내용은 `docs/git-workflow.md`를 필요할 때 `Read`한다(자동 로드되지 않는다).

- **작업 시작**: 해당 에픽 이슈를 확인하고 `feature/<에픽번호>-<설명>` 브랜치를 생성한 뒤 작업한다. main에 직접 커밋하지 않는다.
- **커밋**: Conventional Commits 규칙(`feat`/`fix`/`refactor`/`docs`/`chore`/`test`)을 따른다. 제목은 `타입: 한국어 설명`, 본문은 `[변경 내용]`/`[영향 범위]` 블록으로 작성한다. 기능 단위로 작게 나눠 커밋한다. 커밋 전 반드시 빌드 통과와 로컬 린트(`swiftlint lint --strict` + `swiftformat --lint .`)를 확인한다 — CI `lint.yml`이 둘 다 돌리므로 한쪽만 통과하면 부족하다.
- **PR 제목**: 커밋 제목과 동일하게 `타입: 한국어 설명` 형식을 따른다.
- **커밋 메시지**: Claude 공동저자 서명이나 AI 생성 표식을 넣지 않는다 (히스토리를 깔끔하게 유지).
- **PR 생성**: `gh pr create`를 사용한다. 본문은 `.github/pull_request_template.md` 형식을 채운다. 관련 이슈를 `Closes #<번호>`로 연결하고, UI 변경 시 스크린샷 확인 결과를 기술한다.
- **PR 병합**: 사용자가 직접 검토 후 Squash merge로 수행한다. Claude는 병합을 실행하지 않는다.
- **확인 절차**: 커밋·PR·브랜치 생성은 실행 전에 내용을 먼저 보여주고 사용자 확인을 받은 뒤 진행한다.
