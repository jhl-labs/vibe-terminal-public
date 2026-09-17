import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/recoverable_json_file.dart';
import 'pane_layout.dart';

abstract interface class PaneLayoutRepository {
  Future<Map<String, SessionPaneLayout>> load();
  Future<void> save(Map<String, SessionPaneLayout> layouts);
}

class JsonPaneLayoutRepository implements PaneLayoutRepository {
  JsonPaneLayoutRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<File> _file() async =>
      File('${(await _directory()).path}/pane_layouts.json');
  @override
  Future<Map<String, SessionPaneLayout>> load() async {
    final file = await _file();
    final data = await readRecoverableJson(file);
    if (data == null) return {};
    if (data is! Map) throw const FormatException('배치 파일 형식 오류');
    final version = data['schemaVersion'];
    if (version != null && version != 2) {
      throw const FormatException('지원하지 않는 배치 버전입니다. 원본을 유지합니다.');
    }
    if (version == null) {
      final backup = File('${file.path}.v1-backup');
      if (!await backup.exists() && await file.exists()) {
        await file.copy(backup.path);
      }
    }
    final groups = version == 2 ? data['groups'] : data;
    if (groups is! Map) throw const FormatException('그룹 배치 형식 오류');
    final result = {
      for (final e in groups.entries)
        if (e.key is String)
          e.key as String: SessionPaneLayout.fromJson(e.value),
    };
    if (version == 2 &&
        await file.exists() &&
        groups.entries.any(
          (e) =>
              e.key is String &&
              jsonEncode(result[e.key]?.toJson()) != jsonEncode(e.value),
        )) {
      final backup = File('${file.path}.before-repair');
      if (!await backup.exists()) await file.copy(backup.path);
    }
    return result;
  }

  @override
  Future<void> save(Map<String, SessionPaneLayout> layouts) async {
    final file = await _file();
    // Never overwrite a newer application's document, including on retry.
    if (await file.exists()) {
      final old = jsonDecode(await file.readAsString());
      if (old is Map &&
          old['schemaVersion'] != null &&
          old['schemaVersion'] != 2) {
        throw const FormatException('새 버전의 배치 파일을 덮어쓸 수 없습니다.');
      }
    }
    await writeRecoverableJson(
      file,
      jsonEncode({
        'schemaVersion': 2,
        'groups': {for (final e in layouts.entries) e.key: e.value.toJson()},
      }),
    );
  }
}
