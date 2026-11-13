---
name: write-plans
description: Use when an iOS/Swift spec document exists and needs to become a sub-agent-friendly implementation plan with explicit tasks, file paths, test points, and ordering — before any code is written.
---

# ax: Write Plans

프로젝트 규약(plan 문서 경로 등)은 리포 루트의 `.claude/ax.md`에 있다. 있으면 **먼저 읽는다.**

## Overview
spec을 태스크 단위로 쪼갠 plan 문서로 만든다. 각 태스크는 **독립 서브에이전트가 컨텍스트를 다시 유도하지 않고** 바로 집을 수 있어야 한다.

## When to Use
- spec 문서가 있고 구현이 시작되지 않았다.
- NOT: 파일 하나 고치면 끝나는 변경 → 바로 `/ax:execute-plans`.

## Task Structure

각 태스크는 반드시 아래를 포함한다:

```markdown
### Task N: <짧은 제목>
- **파일 경로**: 생성/수정 예상 파일 (전체 경로)
- **의존성**: 선행 태스크 번호 또는 "없음"
- **테스트 포인트**: 완료를 무엇으로 검증하는지 (테스트 이름, 시뮬레이터에서 확인할 화면 동작)
- **작업 내용**: 무엇을 왜 (구현 세부사항 아님)
- **실행 주체**: `ax:executor` 서브에이전트 / 메인 세션 / **manual(사람이 Xcode에서)**
```

## Ordering Rules
- 공유 파일도 의존성도 없는 태스크 → 독립 표시, `ax:executor` 서브에이전트로 병렬 가능.
- 같은 파일을 건드리는 태스크 → 순차. 순서를 명시한다.
- `.pbxproj` / `*.entitlements` / 배포 타깃 설정을 건드리는 태스크 → **manual**로 표시. 서브에이전트 태스크가 아니다. 이유는 `/ax:execute-plans` 참고.

## Quick Reference

| Plan smell | Fix |
|---|---|
| 파일 경로가 없다 | 서브에이전트에 넘기기엔 너무 모호 — 더 쪼갠다 |
| 테스트 포인트가 없다 | 완료 판정 불가 — 확정 전에 추가 |
| 두 태스크가 조용히 같은 파일을 건드린다 | 의존성을 명시하거나 합친다 |
| 완료 조건은 사용자 눈에 보이는 동작인데 View 파일을 건드리는 태스크가 없다 | **어느 태스크가 그 가시적 결과를 만드는지, 왜 View 변경이 불필요한지**를 적는다 (예: "`@Observable` 상태 변경이 기존 뷰를 다시 그린다"). 안 적으면 화면 작업이 통째로 빠진 계획처럼 읽힌다 — 실제로 실행 도중 질문이 나왔다. 이 "View 변경 불필요" 주장은 사실이 아니라 **시뮬레이터에서 확인할 가정**으로 다룬다 |
| mock/서비스에 하드코딩된 인위적 지연(`Task.sleep` 등)을 추가한다 | 지연을 주입 가능한 파라미터로(기본값 = 실제 값). 테스트가 0에 가깝게 넣어 벽시계 시간을 안 먹게. **지연을 소유하는 타입을 감싸는 모든 타입에 끝까지 관통시킨다** — ViewModel이 지연 헬퍼를 내부에서 생성하면 ViewModel 테스트는 여전히 실제 시간을 다 먹는다. 태스크에 명시적으로 적는다 |

## Common Mistakes
- 이름/시그니처 변경을 호출부 수정과 다른 태스크로 쪼개기 — 앞 태스크가 단독으로 빌드도 테스트도 안 된다. 타입/함수 이름을 바꾸는 태스크는 호출부 갱신을 **같은 태스크에** 넣는다.
- plan을 서술형 산문으로 쓰기 — 서브에이전트에 필요한 건 구조지 이야기가 아니다.
- "같은 화면이니까" 무관한 기능을 한 태스크에 묶기 — 독립적으로 변하는 단위로 쪼갠다.

## 세션 경계
plan 확정 후 이 세션을 끝낸다. 태스크는 **하나에 한 세션**(또는 한 서브에이전트)으로 `/ax:execute-plans`에서 실행한다.
