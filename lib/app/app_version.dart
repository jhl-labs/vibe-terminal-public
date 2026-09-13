import 'package:package_info_plus/package_info_plus.dart';

/// 앱 표시 버전(버전 이름, 예: `0.4.6`). 빌드(pubspec)의 실제 버전을
/// [loadAppVersion]에서 채우므로 버전을 올릴 때 이 값을 따로 고칠 필요가 없다
/// (단일 소스 = pubspec). 업데이트 체크가 이 값을 semver로 파싱하므로 빌드
/// 번호 등으로 오염하면 안 된다.
String kAppVersion = '';

/// 빌드 번호(versionCode, 예: `15`). UI 표기에만 쓰고 업데이트 체크에는 쓰지
/// 않는다. 같은 버전 이름으로 여러 빌드를 배포할 때 테스터가 자기 빌드를
/// 구분할 수 있도록 노출한다.
String kAppBuildNumber = '';

/// 사람에게 보여줄 버전 라벨을 만든다. 빌드 번호가 있으면 `0.4.6 (15)`처럼
/// 덧붙이고, 없으면 버전 이름만, 버전 이름조차 없으면 빈 문자열을 준다.
String appVersionLabel(String version, String buildNumber) {
  if (version.isEmpty) return '';
  if (buildNumber.isEmpty) return version;
  return '$version ($buildNumber)';
}

/// 플랫폼 패키지 정보에서 실제 버전을 읽어 [kAppVersion]/[kAppBuildNumber]에
/// 채운다. 앱 시작 시 1회 호출한다. 실패해도 앱 동작에는 영향이 없다.
Future<void> loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    kAppVersion = info.version;
    kAppBuildNumber = info.buildNumber;
  } catch (_) {
    // 플랫폼 정보를 못 읽는 환경(예: 일부 테스트)에서는 빈 값을 유지한다.
  }
}
