import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';
import 'update_checker.dart';

/// 헤더 배지에 보여줄 "설치 가능한 새 버전".
class PendingUpdate {
  const PendingUpdate({required this.version, required this.url});

  final String version;
  final Uri url;
}

/// 업데이트 알림이 기억해야 하는 최소한의 상태.
///
/// 설정 화면에 노출하는 값이 아니므로 [AppSettings]에 섞지 않고 별도 파일에
/// 둔다. 손상되거나 없으면 그냥 기본값으로 시작하면 되는 성격의 데이터다.
class UpdateState {
  const UpdateState({
    this.skippedVersion,
    this.lastCheckedAt,
    this.latestVersion,
    this.latestUrl,
  });

  /// 사용자가 "이 버전 건너뛰기"를 누른 버전. 더 새로운 버전이 나오면 다시
  /// 알린다.
  final String? skippedVersion;

  /// 마지막으로 GitHub Release를 조회한 시각(UTC).
  final DateTime? lastCheckedAt;

  /// 마지막 조회에서 본 최신 안정 버전과 릴리즈 페이지. 하루 1회 제한 때문에
  /// 조회를 건너뛴 실행에서도 헤더 배지를 그릴 수 있도록 기억한다.
  final String? latestVersion;
  final Uri? latestUrl;

  /// 앱을 자주 켜고 끄는 사용자에게 매번 네트워크를 쓰지 않도록 하루 1회로
  /// 제한한다.
  static const throttle = Duration(hours: 24);

  bool shouldCheck(DateTime now) {
    final last = lastCheckedAt;
    if (last == null) return true;
    // 시계를 뒤로 돌린 기기에서 영원히 체크가 막히지 않도록 미래 값은 무시한다.
    if (last.isAfter(now)) return true;
    return now.difference(last) >= throttle;
  }

  bool isSkipped(String version) => skippedVersion == version;

  /// [currentVersion]보다 새롭고 사용자가 건너뛰지 않은 버전이 알려져 있으면
  /// 그 정보를, 아니면 null을 준다.
  PendingUpdate? pendingUpdate(String currentVersion) {
    final version = latestVersion;
    final url = latestUrl;
    if (version == null || url == null) return null;
    if (isSkipped(version)) return null;
    if (compareVersions(version, currentVersion) <= 0) return null;
    return PendingUpdate(version: version, url: url);
  }

  UpdateState copyWith({
    String? skippedVersion,
    DateTime? lastCheckedAt,
    String? latestVersion,
    Uri? latestUrl,
  }) => UpdateState(
    skippedVersion: skippedVersion ?? this.skippedVersion,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    latestVersion: latestVersion ?? this.latestVersion,
    latestUrl: latestUrl ?? this.latestUrl,
  );

  Map<String, Object?> toJson() => {
    if (skippedVersion != null) 'skippedVersion': skippedVersion,
    if (lastCheckedAt != null)
      'lastCheckedAt': lastCheckedAt!.toUtc().toIso8601String(),
    if (latestVersion != null) 'latestVersion': latestVersion,
    if (latestUrl != null) 'latestUrl': latestUrl.toString(),
  };

  static UpdateState fromJson(Map<String, Object?> json) {
    final skipped = json['skippedVersion'];
    final checked = json['lastCheckedAt'];
    final latest = json['latestVersion'];
    final url = json['latestUrl'];
    return UpdateState(
      skippedVersion: skipped is String && skipped.isNotEmpty ? skipped : null,
      lastCheckedAt: checked is String ? DateTime.tryParse(checked) : null,
      latestVersion: latest is String && latest.isNotEmpty ? latest : null,
      latestUrl: url is String ? Uri.tryParse(url) : null,
    );
  }
}

/// [UpdateState]를 앱 지원 디렉터리의 작은 JSON 파일로 읽고 쓴다.
class UpdatePreferences {
  UpdatePreferences({Future<File> Function()? fileResolver})
    : _fileResolver = fileResolver ?? _defaultFile;

  final Future<File> Function() _fileResolver;

  static Future<File> _defaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}update_state.json');
  }

  Future<UpdateState> load() async {
    try {
      final file = await _fileResolver();
      if (!file.existsSync()) return const UpdateState();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return const UpdateState();
      return UpdateState.fromJson(decoded);
    } catch (_) {
      // 업데이트 알림은 부가 기능이다. 읽지 못하면 처음 보는 상태로 둔다.
      return const UpdateState();
    }
  }

  Future<void> save(UpdateState state) async {
    try {
      await writeFileAtomically(
        await _fileResolver(),
        jsonEncode(state.toJson()),
      );
    } catch (_) {
      // 저장에 실패하면 다음 실행에서 한 번 더 알리는 정도의 손해만 있다.
    }
  }
}
