# 테스트 / 린트 (선택)

앱 실행에는 필요 없습니다. 검증할 때만 참고합니다.

## 테스트

Xcode: **⌘U** (Product → Test) — `AIChatTests` + `AIChatUITests`

또는 CLI (Xcode 커맨드라인 도구 필요).
**반드시 `AIChat/` 디렉터리에서** 실행합니다 (`.xcodeproj`가 있는 위치). 레포 루트(`foamy-dresser` 등)에서 돌리면 프로젝트를 못 찾습니다.

```bash
# 레포 루트 기준
cd AIChat

xcodebuild test \
  -scheme AIChat \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

출력을 보기 좋게 하려면 (선택, `brew install xcbeautify`):

```bash
cd AIChat
xcodebuild test \
  -scheme AIChat \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  | xcbeautify
```

시뮬레이터 이름은 로컬에 설치된 기기 목록에 맞게 바꿉니다 (`xcrun simctl list devices available`).

## 린트

CI(`.github/workflows/lint.yml`)와 동일하게 로컬에서 돌릴 때만. CI는 SwiftLint·SwiftFormat 버전을 `lint.yml`의 `env`에 고정해 두므로, 로컬도 같은 버전을 쓴다 (`swiftlint version`, `swiftformat --version`으로 확인):

```bash
brew install swiftlint swiftformat   # 최초 1회
swiftlint lint --strict
swiftformat --lint .
```
