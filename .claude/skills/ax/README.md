# ax 플러그인

**정본은 `~/.claude/skills/ax/`(전역, `ax@skills-dir`)이다.** 이 디렉터리는 그 사본이다.

## 로드 상태

이 복사본은 프로젝트 플러그인으로 **발견되지만 로드되지 않는다** — 같은 이름의 전역 `ax`가 shadow한다.
(`claude plugin list`가 `✘ Not loaded — your ~/.claude/skills/ax (same plugin name "ax") shadowed the project's ./.claude/skills/ax` 로 알려준다.)

즉 이 레포에서 `/ax:*`를 쓰면 항상 **전역 사본**이 돈다. 여기를 고쳐도 동작은 안 바뀐다.
전역 사본이 없는 사람이 이 레포를 clone하면 이쪽이 대신 로드되므로, 폴백 역할은 한다.

## 동기화

전역 → 이 디렉터리 (한 방향. 반대로 하지 않는다):

```bash
rsync -a --delete --exclude README.md ~/.claude/skills/ax/ "$(git rev-parse --show-toplevel)/.claude/skills/ax/"
```

전역 사본을 고쳤으면(특히 `/ax:retro`가 SKILL.md를 자가수정한 경우) 위 명령으로 맞추고 함께 커밋한다.

## 구성

| | |
|---|---|
| `skills/` | 7개 파이프라인 스킬 → `/ax:write-specs` … `/ax:retro` |
| `agents/` | 4개 서브에이전트 (모델 고정: executor·tester·docs = sonnet, reviewer = opus) |

프로젝트별 경로·컨벤션·제약은 여기가 아니라 `.claude/ax.md`에 있다. 스킬은 실행 시 그 파일을 읽는다.
