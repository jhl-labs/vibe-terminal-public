/// Current desktop distribution edition.
enum AppEdition {
  core('Core');

  const AppEdition(this.label);

  /// UI에 보여줄 이름.
  final String label;

  /// 현재 빌드의 에디션.
  static const current = AppEdition.core;
}

/// 헤더에 표시할 `에디션 버전` 문자열. 버전을 아직 못 읽었으면 에디션만 준다.
String appEditionLabel(AppEdition edition, String version) {
  if (version.isEmpty) return edition.label;
  return '${edition.label} $version';
}
