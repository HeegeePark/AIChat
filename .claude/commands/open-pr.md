---
description: 템플릿 기반 PR 생성
argument-hint: <에픽 이슈번호>
allowed-tools: Bash(git *), Bash(gh *), Read
---
# PR 생성
1. 현재 브랜치의 커밋들을 요약
2. PR 제목은 `타입: 한국어 설명` 형식 (예: `feat: 카카오 로그인 연동`)
3. .github/pull_request_template.md 형식으로 PR 본문 작성 (Closes #$ARGUMENTS 포함)
4. UI 변경이 있으면 스크린샷 확인 결과를 본문에 기술
5. 본문을 보여주고 확인받은 뒤 gh pr create 실행. 병합은 하지 않는다.
