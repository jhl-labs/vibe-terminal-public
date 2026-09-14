# Vibe Terminal

Linux, Windows, macOS를 지원하는 빠른 크로스플랫폼 SSH 터미널 앱입니다.

[English](README.md)

## 주요 기능

- **완전한 터미널 에뮬레이션** — xterm 호환 렌더링과 ANSI 컬러를 지원하며, 줌인/줌아웃으로 글자 크기를 조정할 수 있습니다.
- **호스트 및 세션 관리** — 세션 그룹으로 연결을 정리하고, 한 번의 클릭으로 재접속하며, 여러 세션을 동시에 열어둘 수 있습니다.
- **SSH 점프 호스트 & Kubernetes** — bastion/점프 호스트를 경유해 접속하고, Kubernetes pod로 SSH 세션을 열 수 있습니다.
- **로컬 터미널** — SSH 세션과 함께 같은 창에서 로컬 셸을 열 수 있습니다.
- **스니펫 패널** — 자주 쓰는 명령어를 저장하고 재사용합니다.
- **AI Chat 패널** — 작업 중에 AI와 대화할 수 있는 사이드 패널입니다.
- **메모 패널** — 터미널 세션 옆에서 바로 메모를 남길 수 있습니다.
- **Community 패널** — 다른 사용자들과 자료를 공유하고 탐색합니다.
- **CLI 도구 연동** — 시스템에 Claude Code, Codex, OpenCode가 설치되어 있으면 관련 설정을 자동으로 노출합니다.
- **안전한 자격증명 저장** — 호스트 자격증명은 OS 레벨 보안 저장소에 저장됩니다.
- **이미지 붙여넣기** — 지원되는 전송 방식에 이미지를 바로 붙여넣을 수 있습니다.
- **적응형 엣지 패널** — 접을 수 있는 사이드 드로어로 데스크톱과 좁은 창에서도 인터페이스가 복잡해지지 않습니다.

## 시작하기

```sh
flutter pub get
flutter analyze
```

### 빌드

```sh
# Linux
flutter build linux --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release
```

각 플랫폼의 빌드된 바이너리는 [Releases](../../releases) 페이지에서 받을 수 있습니다.

## 라이선스

이 프로젝트는 소스 공개형 라이선스로 배포됩니다 — [LICENSE](LICENSE)를 참고하세요. 번들된 터미널 런타임 의존성의 서드파티 라이선스는 `vendor/*/LICENSE`에 있습니다.

## 기여

[CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요. 보안 취약점은 공개 이슈 대신 비공개로 제보해 주세요 — [SECURITY.md](SECURITY.md).
