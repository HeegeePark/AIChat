# 문제 해결

빌드/실행 중 겪을 수 있는 증상과 확인 방법입니다.

| 증상 | 확인 |
|------|------|
| 빌드/동시성 관련 오류가 난다 | **Xcode 26**으로 열고 있는지 (구버전 Xcode는 Swift 6.3/프로젝트 설정과 어긋날 수 있음) |
| 시뮬레이터가 목록에 없다 | Xcode → Settings → Platforms에서 **iOS 17.0+** 런타임 설치 |
| zip 해제 후 프로젝트를 못 찾겠다 | 경로가 `…/AIChat/AIChat.xcodeproj`인지 확인 (중첩 `AIChat` 폴더) |
| Code Signing / Team 오류 | **Signing & Capabilities**에서 Team·Bundle ID를 본인 것으로 맞추기. Destination은 **시뮬레이터** 권장 (실기기 불필요) |
| 실행은 되는데 이전 대화가 남는다 | 시뮬 **Device → Erase All Content and Settings** 또는 앱 삭제 후 재설치 (로컬 영속화) |
| `xcodebuild: … does not contain an Xcode project` | 작업 디렉터리가 레포 루트임 → `cd AIChat` 후 재실행 (또는 `-project AIChat/AIChat.xcodeproj`를 루트에서 지정) |
| `xcbeautify: unexpected arguments: '#' …` | 명령 줄 끝의 한글 주석(`# …`)이 zsh 대화형에서 인자로 해석됨 → 주석 없이 실행하거나 별도 줄에 설명 |
