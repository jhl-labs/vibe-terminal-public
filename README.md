# Vibe Terminal Public

기존 Vibe Terminal UI와 호스트 관리, SSH/로컬 터미널, 세션 그룹, 스니펫을 유지하는 공개 소스 구성입니다.

우측 사이드 앱 중 X11, Agent Chat, Port Forward, SFTP, Vault, Browser를 제외합니다. AI Chat, 메모, CLI 설정, Community, 로그는 기존 패널을 사용합니다. 제외된 패널과 전용 서비스 구현은 이 저장소에 없으며 빌드 플래그로 활성화할 수 없습니다. CLI 설정은 해당 Claude·Codex·OpenCode 실행 파일이 시스템에 설치된 경우에만 표시합니다. 원격 Run URL의 자동 터널도 포함하지 않습니다.

호스트·세션·설정 파일 포맷에 남은 호환 필드는 비공개 기능을 실행하지 않습니다. 기존 SSH 점프 호스트, Kubernetes SSH 연결과 이미지 붙여넣기에 필요한 전송 동작은 유지합니다. SFTP 파일 탐색 앱의 구현은 포함하지 않습니다.

Flutter 3.47.2에서 macOS 빌드와 실행을 검증합니다.

```sh
flutter pub get
flutter analyze
flutter build macos --release
open 'build/macos/Build/Products/Release/Vibe Terminal Public.app'
```

Windows/Linux 러너도 포함되어 있습니다. 해당 운영체제에서 `flutter build windows --release` 또는 `flutter build linux --release`를 사용합니다. 해당 플랫폼은 아직 실행 검증하지 않았습니다.

macOS 공개판은 별도 앱 식별자와 저장소를 사용합니다. 서드파티 라이선스는 `vendor/*/LICENSE`에 있습니다. 앱 자체의 공개 배포 라이선스는 아직 지정하지 않았습니다.
