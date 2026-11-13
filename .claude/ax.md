# ax 파이프라인 — 이 프로젝트 규약

전역 `ax:*` 스킬(`~/.claude/skills/ax/`)이 참조하는 프로젝트별 사실. 스킬 본문의 기본값보다 **이 문서가 우선**한다.
매 세션 자동 로드되지 않는다 — `ax:*` 스킬이 실행될 때만 읽힌다.

## 경로

| 용도 | 경로 |
|---|---|
| spec 문서 | `docs/specs/<slug>.md` |
| plan 문서 | `docs/plans/<slug>.md` |
| 함정 문서 | `docs/gotchas.md` — 인덱스는 `CLAUDE.md`의 「함정 사전」 섹션 |
| Git/PR 규약 | `docs/git-workflow.md` (`ax:refresh-docs` 대상 아님) |
| 소스 루트 | `AIChat/AIChat/` |

## 환경 기본값

`.claude/settings.json`의 `env`:
- `IOS_DEPLOYMENT_TARGET` = 17.0 → spec의 「플랫폼 제약」 기본값
- `DEFAULT_SIMULATOR` = iPhone 16 → **이름만 믿지 말 것.** 이 머신에서 iPhone 16은 구 런타임(iOS 18.6)에 묶여 있다. `list_sims`의 `runtime`을 확인하고 최신 런타임(iPhone 17류) 기기를 고른다. 상세는 `CLAUDE.md` 빌드/검증 섹션.

## `ax:write-specs` — 이슈 선행 생성

이 레포는 에픽 하위 항목마다 GitHub Task 이슈를 먼저 만들고 spec 헤더가 그 번호를 참조한다.
- spec 헤더: `- 상위 에픽: #N` / `- 하위 이슈: #N`
- 에픽 체크리스트 줄이 아직 평문이면 **먼저** Task 이슈를 만들고(내용을 사용자에게 확인받은 뒤 `gh issue create`), 그 줄을 `- [ ] #<번호>`로 교체한다.
- 체크리스트 항목 하나 = 이슈 하나. 연속된 하위 항목을 하나로 합치지 않는다 — 대신 "의존 태스크"로 링크한다.

## `ax:execute-plans` — 파일 보호

- `.claude/hooks/file-protection.sh`가 `.pbxproj`/`.entitlements`/`.xcconfig`/`project.yml` 편집을 실제로 차단한다. 훅이 아직 못 잡는 패턴이라도 규칙은 구속력이 있다.
- **예외**: 이 프로젝트는 Xcode 16+ file system synchronized group을 쓴다(`objectVersion = 77`). `AIChat/AIChat/` 하위 **파일 추가/삭제는 `.pbxproj` 편집 없이 자동 반영**되므로 허용된다. 금지 대상은 프로젝트 **설정** 변경이다.
- 워크트리 병렬 작업 시 같은 번들 ID를 덮어쓰므로, 워크트리마다 `list_sims`에서 서로 다른 UDID를 골라 `session_set_defaults`로 고정한다. 이미 `Booted`인 기기는 다른 세션이 쓰는 중일 수 있으니 `Shutdown` 기기를 새로 부팅한다.

## `ax:refresh-docs` — 체크리스트 단위

`README.md`의 「기능 현황」 체크리스트는 **태스크(하위 이슈) 단위가 아니라 Phase(에픽) 단위**다.
- 에픽의 마지막 통합 태스크가 완료될 때만 체크한다.
- 개별 태스크 PR에서는 건드리지 않는다.

## `ax:retro` — 목적지

- 기본값: `docs/gotchas.md`. 새 절을 만들면 `CLAUDE.md` 「함정 사전」에 **증상 문장** 한 줄을 추가한다.
- 이 프로젝트는 `CLAUDE.md` 비대화 때문에 한 번 분리했다. 되돌리지 않는다.
- 이 레포는 git worktree(`.superset/worktrees/AIChat/<name>`)에서 작업하는 경우가 있다. 주 체크아웃은 `~/Desktop/Repositories/PERSONAL/AIChat`. 경로는 반드시 `git rev-parse --show-toplevel`로 resolve한다.
