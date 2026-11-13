---
name: refresh-docs
description: Use when an iOS/Swift feature or fix is code-complete and reviewed, and README, ARCHITECTURE, or CHANGELOG docs need to be brought up to date — focused on why decisions were made, not restating the code.
---

# ax: Refresh Docs

프로젝트별 문서 규약(어떤 문서가 이 스킬 대상인지, 체크리스트 단위 등)은 리포 루트의 `.claude/ax.md`에 있다. **먼저 읽는다** — 프로젝트마다 다르다.

## Overview
구현 후 문서를 갱신한다. 세 파일로 범위를 묶어 번지지 않게 한다: README, ARCHITECTURE(있으면), CHANGELOG(있으면).

## When to Use
- `/ax:review-code`와 `/ax:check-quality`가 통과한 뒤, `/ax:retro` 직전.
- NOT: 코드만 봐도 명확한 구현 디테일 문서화 — 거기엔 주석을 쓰거나 아무것도 안 쓴다.

## 실행 방식
`ax:docs` 서브에이전트에 넘길 수 있다. 프롬프트에 `git diff`의 파일 목록 + 대상 문서 경로만 준다.

## Scope

| 문서 | 무엇을 적나 |
|---|---|
| `README.md` | 사용자/개발자가 알아야 할 설정법, 기능 목록 변경 |
| `ARCHITECTURE.md` (있으면) | 구조가 바뀐 **이유** — 무엇이 바뀌었는지가 아니라 왜 |
| `CHANGELOG.md` (있으면) | 사용자 관점에서 무엇이 달라졌는지, 한 줄 |

## Rules
- 코드 주석과 중복되는 내용을 쓰지 않는다 — "무엇을"은 코드가 말한다, 문서는 "왜"를 남긴다.
- **없는 문서 파일을 이 스킬이 새로 만들지 않는다.** 사용자가 명시적으로 요청할 때만.
- 워크플로우 문서(git 규약 등)는 이 스킬의 대상이 아니다.
- README 기능 체크리스트의 **단위**를 확인한다 — 프로젝트에 따라 태스크 단위가 아니라 에픽/Phase 단위일 수 있다. `.claude/ax.md`에 명시돼 있으면 그걸 따르고, 없으면 임의로 체크하지 말고 물어본다.

## Common Mistakes
- 코드 변경사항을 복붙해 "What" 위주로 쓰기 — 리뷰어는 diff로 이미 안다. 문서엔 이유를 쓴다.
- 매 태스크마다 CHANGELOG 갱신 — 기능 단위(PR 단위)로 한 번.

## 세션 경계
문서 갱신 후 이어서 `/ax:retro`를 **같은 세션에서** 돌린다 — 회고의 입력은 이번 파이프라인에서 실제로 어긋난 지점이라, 컨텍스트가 살아 있어야 한다.
