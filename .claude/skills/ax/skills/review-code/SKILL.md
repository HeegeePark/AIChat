---
name: review-code
description: Use when reviewing recently implemented Swift/SwiftUI code before it ships — covers over-engineering, Swift concurrency safety, dependency direction, and HIG/accessibility basics. Runs in an isolated sub-agent so the reviewer did not write the code.
---

# ax: Review Code

프로젝트별 아키텍처 원칙·금지 항목은 리포 루트의 `.claude/ax.md`와 `CLAUDE.md`에 있다. **먼저 읽는다.**

## Overview
구현된 코드를 두 축으로 리뷰한다: 단순성(ponytail)과 iOS 고유 정확성(동시성, 아키텍처, 접근성) — 후자는 ponytail만으로는 안 잡힌다.

## When to Use
- 태스크/plan 구현이 끝나 커밋/PR 직전.
- NOT: `/ax:check-quality`(테스트)의 대체재가 아니다. 이건 읽기 리뷰다.

## 실행 방식 — 컨텍스트 격리 (필수)

**코드를 작성한 세션에서 리뷰하지 않는다.** 작성 컨텍스트가 남아 있으면 "왜 그렇게 썼는지"를 이미 알아서 그 이유를 재검증하지 않는다.

`ax:reviewer` 서브에이전트에 넘긴다. 프롬프트에는 **diff 범위만** 준다 (`git diff main...HEAD`의 대상 파일 목록 + 리뷰 요청). 설계 의도 설명을 붙이지 않는다 — 코드만 보고 의도가 안 읽히면 그 자체가 발견 사항이다.

## Checklist

**단순성 (ponytail)**
- 불필요한 추상화(단일 구현체 프로토콜, 안 쓰이는 설정값)가 있는가
- 이미 있는 헬퍼/타입을 재구현하지 않았는가

**Swift Concurrency**
- `@MainActor`가 UI를 만지는 타입/메서드에 붙어 있는가
- 크로스-액터로 넘어가는 타입이 `Sendable`을 만족하는가 (혹은 왜 안 해도 되는지 명확한가)
- 불필요한 `Task { }` 남발이나 구조화되지 않은 동시성이 없는가

**의존성 방향**
- 하위 레이어(모델/서비스)가 상위 레이어(뷰)를 참조하지 않는가
- 순환 참조가 생기지 않았는가

**HIG / Accessibility 기본**
- 터치 타겟이 44x44pt 이상인가
- `accessibilityLabel`/`accessibilityHint`가 의미 있는 커스텀 컨트롤에 붙어 있는가
- Dynamic Type을 깨는 고정 폰트 크기를 쓰지 않았는가
- 다크/라이트 양쪽에서 색상 대비가 있는가 — 하드코딩 RGB나 `.opacity()` 블렌딩이 보이면 **추측하지 말고** `xcrun simctl ui <UDID> appearance dark`로 전환해 스크린샷으로 확인한다

## Output Format

발견 사항당 한 줄: `파일:라인 — 문제 — 제안`. 항목마다 에세이를 쓰지 않는다.

## Common Mistakes
- "컴파일되는가"만 보기 — 그건 `/ax:execute-plans`의 몫. 이 리뷰는 빌드가 된다고 전제한다.
- 스타일 취향을 이슈로 올리기 — 동시성/아키텍처/HIG/접근성 문제와 진짜 과설계만 올린다.
- 서브에이전트에 "이건 이래서 이렇게 했어" 배경을 주기 — 격리의 목적을 스스로 깬다.

## 반영 전 검증 (필수)

**리뷰 지적을 그대로 반영하지 않는다. 지적한 시나리오가 실제 코드 흐름에서 성립하는지 먼저 확인한다.**

리뷰어는 콜드 컨텍스트라 코드를 정확히 읽지만 도달 가능성을 놓친다. 지적마다 두 가지를 따로 확인한다:
- **재현 경로가 있는가** — 그 상태에 실제로 도달하는가, 아니면 앞선 코드가 이미 막고 있는가.
- **인용이 사실인가** — 파일:라인, "레포에 이미 이런 패턴이 있다" 같은 근거를 직접 열어 확인한다. 단, **검증 명령이 "없음"을 반환하면 도구 문법부터 의심할 것** — 잘못된 0건으로 정확한 지적을 기각한 사례가 있다.

성립하지 않는 지적을 반영하면 없던 버그가 생긴다(실사례: "반복 재시도가 겹칠 수 있다"는 지적을 받아 공유 Task 취소를 넣었는데, 같은 대상의 반복 재시도는 애초에 불가능했고 **서로 다른 대상의 독립 요청끼리 취소되는** 더 나쁜 동작이 됐다. 이후 `/ax:check-quality`의 "이 줄을 지워도 통과하는가"로 발각).

반영한 지적마다 회귀 테스트를 남기고, **그 테스트가 수정을 되돌리면 실제로 실패하는지** 확인한다.

지적을 반영한 뒤에는 **같은 콜드 리뷰어에게 수정된 diff만 다시 보여 no findings까지 재검토한다.** 한 취소 경합을 닫는 cleanup이 인접 terminal path의 원본까지 지우는 것처럼, 첫 수정이 같은 상태 머신의 다음 경합을 열 수 있다. 재리뷰에서 새 지적이 나오면 위의 도달 가능성·인용 검증과 mutation 테스트 절차를 반복한다.

## 세션 경계
리뷰 결과를 반영한 뒤 `/ax:check-quality`로 넘어간다.
