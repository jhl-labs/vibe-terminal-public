import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 세션별 자율사용 토글. 카운터·대기 상태는 저장하지 않는다(재시작 후 새로 판정).
class AutopilotPrefs {
  const AutopilotPrefs({
    required this.enabled,
    required this.notifyOnly,
    this.hostId,
  });

  final bool enabled;
  final bool notifyOnly;

  /// 저장 당시 세션의 호스트 id. 세션 id(`sN`)는 재사용될 수 있으므로 복원할 때
  /// 같은 호스트의 복원된 세션인지 대조한다. 없으면(이전 형식) 복원하지 않는다.
  final String? hostId;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'notifyOnly': notifyOnly,
    if (hostId != null) 'hostId': hostId,
  };

  static AutopilotPrefs? fromJson(Object? value) {
    if (value is! Map) return null;
    final enabled = value['enabled'];
    if (enabled is! bool) return null;
    return AutopilotPrefs(
      enabled: enabled,
      notifyOnly: value['notifyOnly'] == true,
      hostId: value['hostId'] is String ? value['hostId'] as String : null,
    );
  }
}

abstract interface class AutopilotPrefsStore {
  Future<Map<String, AutopilotPrefs>> load();
  Future<void> save(Map<String, AutopilotPrefs> prefs);
}

/// 앱 지원 디렉터리의 `autopilot.json`. 세션 id는 복원 시 그대로 유지된다
/// (`SessionManager` 복원이 `RestoredSessionEntry.id`를 재사용).
class FileAutopilotPrefsStore implements AutopilotPrefsStore {
  FileAutopilotPrefsStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  Future<void> _pending = Future<void>.value();

  Future<File> _file() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}autopilot.json',
  );

  @override
  Future<Map<String, AutopilotPrefs>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String)
            if (AutopilotPrefs.fromJson(entry.value) case final prefs?)
              if (prefs.enabled) entry.key as String: prefs,
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, AutopilotPrefs> prefs) {
    _pending = _pending.then(
      (_) => _write(prefs),
      onError: (_) => _write(prefs),
    );
    return _pending;
  }

  Future<void> _write(Map<String, AutopilotPrefs> prefs) async {
    try {
      final file = await _file();
      final enabled = {
        for (final e in prefs.entries)
          if (e.value.enabled) e.key: e.value.toJson(),
      };
      await file.writeAsString(jsonEncode(enabled));
    } catch (_) {
      // 저장 실패는 토글 동작에 영향을 주지 않는다. 다음 변경 때 다시 쓴다.
    }
  }
}

class MemoryAutopilotPrefsStore implements AutopilotPrefsStore {
  MemoryAutopilotPrefsStore([Map<String, AutopilotPrefs>? initial])
    : saved = {...?initial};

  Map<String, AutopilotPrefs> saved;

  @override
  Future<Map<String, AutopilotPrefs>> load() async => {...saved};

  @override
  Future<void> save(Map<String, AutopilotPrefs> prefs) async {
    saved = {
      for (final e in prefs.entries)
        if (e.value.enabled) e.key: e.value,
    };
  }
}

final autopilotPrefsStoreProvider = Provider<AutopilotPrefsStore>(
  (ref) => FileAutopilotPrefsStore(),
);
