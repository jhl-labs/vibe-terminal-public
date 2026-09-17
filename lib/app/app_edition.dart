/// 배포 에디션. 세션 레일 헤더의 `Core 0.11.0` / `Pro 0.11.0` 라벨에 쓴다.
///
/// - **Core**: 공개(오픈소스) 배포. `public-release` 스킬이 내보내는 파생 저장소.
/// - **Pro**: 이 저장소(원본)에서 만드는 빌드. Core에 없는 전용 기능을 포함한다.
///
/// 어떤 기능이 어느 에디션에 속하는지는 루트 `PRO_EDITION.md`와
/// `.claude/skills/public-release/feature-map.json`이 관리한다.
enum AppEdition {
  core('Core'),
  pro('Pro');

  const AppEdition(this.label);

  /// UI에 보여줄 이름.
  final String label;

  /// 현재 빌드의 에디션. 원본 저장소는 항상 Pro이며, 공개판은 `public-release`
  /// 스킬이 이 파일을 패치해 [core]로 고정한다. `--dart-define`으로 바꿀 수
  /// 없다: 라벨과 실제 포함 기능이 어긋나면 안 되기 때문이다.
  static const current = AppEdition.core;
}

/// 헤더에 표시할 `에디션 버전` 문자열. 버전을 아직 못 읽었으면 에디션만 준다.
String appEditionLabel(AppEdition edition, String version) {
  if (version.isEmpty) return edition.label;
  return '${edition.label} $version';
}
