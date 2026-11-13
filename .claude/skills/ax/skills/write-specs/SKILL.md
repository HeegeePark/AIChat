---
name: write-specs
description: Use when a new iOS/Swift development request (PDF, ticket, feature idea) needs to become a spec document before any planning or coding — turns a raw ask into a spec with explicit platform constraints and pressure-tests it with the user.
---

# ax: Write Specs

프로젝트 규약(경로·이슈 컨벤션·타깃 버전)은 리포 루트의 `.claude/ax.md`에 있다. 있으면 **먼저 읽고** 이 스킬의 기본값보다 우선한다.

## Overview
개발 요청(PDF/이슈/대화)을 spec 문서로 만든다. 먼저 초안을 쓰고, 확정 전에 사용자에게 되물어 압박 테스트한다.

## When to Use
- 새 기능/에픽이 시작됐고 spec이 아직 없다.
- 기존 spec이 플랫폼 제약(버전, 기기, 최신 HIG)에 대해 모호하다.
- NOT: 범위가 자명한 작은 수정 → 바로 `/ax:write-plans` 또는 그냥 고친다.

## Workflow

1. **원본을 끝까지 읽는다.** 쓰기 전에 소스(PDF/이슈/대화)를 전량 읽는다.
2. **이슈 선행 생성.** 프로젝트가 이슈 연동 컨벤션을 쓰면(`.claude/ax.md` 확인) spec 헤더가 참조할 이슈를 **먼저** 만든다. 없는 번호를 헤더에 쓰지 않는다.
3. **초안 작성.** 기본 섹션:
   - 배경 / 목적 (왜 필요한가)
   - 범위 (포함 / 제외)
   - UX 플로우 (화면별 동작)
   - 플랫폼 제약 — **반드시 채울 것**: iOS 지원 버전 범위 / 기기 지원 범위 / 최신 HIG(Liquid Glass 등) 적용 여부
   - 완료 조건 (검증 가능한 문장으로)
4. **압박 테스트.** 확정 전에 `AskUserQuestion`으로 모호한 지점을 명시적으로 답 받는다 — 특히 3의 플랫폼 제약과 원본이 해소 못 한 동작 모호성. iOS 버전 범위·기기 지원·비즈니스 로직 엣지케이스를 **추측하지 않는다.**
   사용자가 "왜?"라고 되물으면 실제 근거(데이터 흐름/결과 추적)를 대답한다. "그게 더 단순해서" 같은 반사적 답은 근거가 아니다. 한 번의 "왜"를 못 버티는 정당화는 아직 안 끝난 것이다.
5. **확정.** 저장하고 다음 단계를 안내한다.

## Quick Reference

| 섹션 | 비워두면 안 되는 것 |
|---|---|
| 플랫폼 제약 | iOS 버전, 기기, 최신 HIG 여부 |
| 완료 조건 | 검증 가능한(테스트 가능한) 문장 |

## Common Mistakes
- 플랫폼 제약을 "코드 짜면서 자연히 정해진다"고 건너뛰기 — `/ax:execute-plans`에서 재작업이 나는 정확한 원인.
- UX 플로우를 구현 용어(뷰 이름, 파일 경로)로 쓰기 — 그건 `/ax:write-plans`의 몫.
- 접근법을 **출처**로 정당화하기 — "요구사항 문서의 예시가 이 API를 암시한다", "setter 의도가 그렇다"는 근거가 아니라 소스다. 이 코드베이스 요구사항에 왜 기술적으로 맞는지(대안은 뭐가 깨지거나 비싼지)를 먼저 말하고, 외부 힌트는 뒤에 보강으로만 붙인다.

## 세션 경계
spec 확정 후 이 세션을 끝낸다. 새 세션에서 `/ax:write-plans`로 시작한다 — 인계물은 대화가 아니라 저장된 spec 문서다.
