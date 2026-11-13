---
name: execute-plans
description: Use when implementing tasks from an ax plan for an iOS/Swift project — covers the XcodeBuildMCP build/fix/test loop, minimal-diff discipline, per-task sub-agent dispatch, and the hard rule against touching Xcode project files.
---

# ax: Execute Plans

프로젝트 규약(빌드 대상, 시뮬레이터 기본값, 보호 훅)은 리포 루트의 `.claude/ax.md`에 있다. 있으면 **먼저 읽는다.**

## Overview
plan의 태스크를 **한 번에 하나씩** 실행하고, 각각을 시뮬레이터 빌드로 검증한다. 코드를 쭉 쓰고 컴파일되길 바라지 않는다.

## The Hard Rule

**에이전트가 절대 직접 수정하지 않는다:**
- `*.pbxproj`
- `*.entitlements`
- 배포 타깃(deployment target) 설정 — Xcode 프로젝트 설정 또는 `project.yml`/`.xcconfig`의 타깃 버전 값

사람이 Xcode에서 해야 한다. 태스크가 이걸 요구하면 **멈추고** 무엇을 수동으로 바꿔야 하는지 알린다 — 파일 편집으로도 `xcodebuild` 플래그로도 시도하지 않는다. 프로젝트에 차단 훅이 있어도 없어도 이 규칙은 구속력이 있다.

> 예외: 프로젝트가 Xcode 16+ file system synchronized group을 쓰면 소스 트리 안의 파일 **추가/삭제**는 `.pbxproj` 편집 없이 자동 반영된다. 금지되는 건 프로젝트 **설정** 변경이지 파일 추가가 아니다. 해당 여부는 `.claude/ax.md`에서 확인한다.

## Workflow

1. plan에서 다음 태스크를 집는다 (의존성 순서 준수).
2. **한 세션 = 한 태스크.** 여러 태스크를 한 컨텍스트에 쌓지 않는다. 독립 태스크가 여럿이면 `ax:executor` 서브에이전트에 하나씩 넘긴다 — 태스크 본문(파일 경로/의존성/테스트 포인트/작업 내용)을 그대로 프롬프트에 복사한다. plan 전체나 대화 이력을 넘기지 않는다.
3. ponytail: 태스크의 작업 내용을 만족하는 **가장 작은 diff**. 새로 쓰기 전에 기존 타입/헬퍼를 먼저 찾는다.
4. 사소하지 않은 변경 직후 빌드 — 검증 안 된 편집을 쌓지 않는다:
   - 세션당 한 번 `mcp__XcodeBuildMCP__session_show_defaults`로 scheme/시뮬레이터 확인.
   - `build_sim` → 에러 수정 → 깨끗해질 때까지 반복.
   - 태스크의 테스트 포인트를 `test_sim`으로 (화면 동작이면 `tap`/`snapshot_ui`/`screenshot`으로).
5. 기능이 "한 기능 단위"를 넘어가면(무관한 화면을 건드림, diff가 더 이상 한 태스크에 안 매핑됨) 멈추고 별도 PR로 쪼갠다.
6. plan 문서에 완료를 표시하고 세션을 닫는다.

## Quick Reference

| 상황 | 조치 |
|---|---|
| 태스크가 `.pbxproj`/entitlements/배포 타깃 변경을 요구 | 멈추고 사용자에게 알림. 편집 금지 |
| 편집 후 빌드 실패 | 다음 태스크로 넘어가기 전에 고친다 — 태스크 사이에 red 빌드를 남기지 않는다 |
| diff가 한 기능 단위를 넘어감 | 새 PR로 분리 |
| 공유 파일 없는 독립 태스크가 여럿 | `ax:executor` 서브에이전트로 태스크당 하나씩 병렬 |

## Common Mistakes
- 전 태스크 코드를 다 쓰고 마지막에 한 번 빌드 — 루프의 의미가 사라진다. 태스크마다 빌드한다.
- "파일 참조만 추가하려고" `project.pbxproj`를 편집 — 작은 편집도 금지다.
- "온 김에" 태스크의 작업 내용을 넘어 과구현 — 태스크에만 머문다.
- 서브에이전트에 대화 전체를 넘기기 — 컨텍스트 격리의 이점이 사라지고 비용만 는다. 태스크 본문만 넘긴다.

## 세션 경계
태스크 하나가 끝나면(빌드+테스트 통과, plan에 체크) 세션을 닫는다. 다음 태스크는 새 세션/새 서브에이전트.
모든 태스크가 끝나면 **새 세션에서** `/ax:review-code`로 넘어간다 — 자기가 쓴 코드를 같은 컨텍스트에서 리뷰하면 편향된다.
