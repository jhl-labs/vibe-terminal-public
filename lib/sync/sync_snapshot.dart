import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'synced_settings.dart';

/// 동기화 파일의 평문 형식 식별자.
const kSyncFormat = 'vibe-terminal-sync';

/// 현재 평문 스냅샷 버전. v2는 레코드별 삭제 기록이 없던 업로드 전용 형식이다.
const kSyncVersion = 3;

/// 섹션 이름. 로컬 테이블 이름과 같게 둔다(삭제 기록의 entity와도 같다).
abstract final class SyncSectionNames {
  static const hosts = 'hosts';
  static const snippets = 'snippets';
  static const memos = 'memos';
  static const sshKeys = 'ssh_keys';
  static const identities = 'identities';
  static const hostKeys = 'host_keys';
}

/// 동기화되는 레코드 하나. [data]에는 비밀값(`secret`)이 들어갈 수 있으며,
/// 스냅샷 전체가 암호화되어 올라간다.
class SyncRecord {
  SyncRecord({
    required this.id,
    required DateTime updatedAt,
    required Map<String, Object?> data,
  }) : updatedAt = updatedAt.toUtc(),
       data = Map.unmodifiable(data);

  final String id;
  final DateTime updatedAt;
  final Map<String, Object?> data;

  String get canonicalData => canonicalJson(data);

  bool sameAs(SyncRecord other) =>
      id == other.id &&
      updatedAt.isAtSameMomentAs(other.updatedAt) &&
      canonicalData == other.canonicalData;

  Map<String, Object?> toJson() => {
    'id': id,
    'updatedAt': updatedAt.toIso8601String(),
    'data': data,
  };

  static SyncRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final updatedAt = _parseDate(json['updatedAt']);
    final data = json['data'];
    if (id is! String || id.isEmpty || updatedAt == null || data is! Map) {
      return null;
    }
    return SyncRecord(
      id: id,
      updatedAt: updatedAt,
      data: Map<String, Object?>.from(data),
    );
  }
}

/// 삭제 기록. 같은 레코드가 이보다 늦게 고쳐지지 않았다면 다른 기기에서도 지운다.
class SyncTombstone {
  SyncTombstone({
    required this.entity,
    required this.id,
    required DateTime deletedAt,
  }) : deletedAt = deletedAt.toUtc();

  final String entity;
  final String id;
  final DateTime deletedAt;

  String get key => keyOf(entity, id);

  static String keyOf(String entity, String id) => '$entity\u0000$id';

  Map<String, Object?> toJson() => {
    'entity': entity,
    'id': id,
    'deletedAt': deletedAt.toIso8601String(),
  };

  static SyncTombstone? fromJson(Object? json) {
    if (json is! Map) return null;
    final entity = json['entity'];
    final id = json['id'];
    final deletedAt = _parseDate(json['deletedAt']);
    if (entity is! String || id is! String || deletedAt == null) return null;
    return SyncTombstone(entity: entity, id: id, deletedAt: deletedAt);
  }
}

/// 동기화 대상 설정 묶음. 묶음 전체가 마지막 변경 시각 하나로 경쟁한다.
class SyncSettingsBlock {
  SyncSettingsBlock({
    required DateTime? updatedAt,
    required Map<String, Object?> values,
  }) : updatedAt = updatedAt?.toUtc(),
       values = Map.unmodifiable(values);

  /// null이면 이 기기에서 아직 동기화 대상 설정을 바꾼 적이 없다.
  final DateTime? updatedAt;
  final Map<String, Object?> values;

  Map<String, Object?> toJson() => {
    'updatedAt': updatedAt?.toIso8601String(),
    'values': values,
  };

  static SyncSettingsBlock? fromJson(Object? json) {
    if (json is! Map) return null;
    final values = json['values'];
    if (values is! Map) return null;
    return SyncSettingsBlock(
      updatedAt: _parseDate(json['updatedAt']),
      values: Map<String, Object?>.from(values),
    );
  }
}

class SyncSnapshot {
  SyncSnapshot({
    this.settings,
    Map<String, List<SyncRecord>> sections = const {},
    List<SyncTombstone> tombstones = const [],
  }) : sections = Map.unmodifiable({
         for (final entry in sections.entries)
           entry.key: List<SyncRecord>.unmodifiable(entry.value),
       }),
       tombstones = List.unmodifiable(tombstones);

  static final empty = SyncSnapshot();

  final SyncSettingsBlock? settings;
  final Map<String, List<SyncRecord>> sections;
  final List<SyncTombstone> tombstones;

  int get recordCount =>
      sections.values.fold(0, (sum, records) => sum + records.length);

  bool get isEmpty => recordCount == 0 && settings == null;

  Map<String, Object?> toJson({DateTime? createdAt}) => {
    'format': kSyncFormat,
    'version': kSyncVersion,
    'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    'settings': settings?.toJson(),
    'sections': {
      for (final name in sections.keys.toList()..sort())
        name: [
          for (final record in _sortedRecords(sections[name]!)) record.toJson(),
        ],
    },
    'tombstones': [
      for (final tombstone in _sortedTombstones(tombstones)) tombstone.toJson(),
    ],
  };

  /// 생성 시각을 뺀 내용의 해시. 같은 내용도 암호문은 매번 달라지므로
  /// 업로드가 필요한지는 이 값으로 판단한다.
  String get contentHash {
    final json = toJson()..remove('createdAt');
    return sha256.convert(utf8.encode(canonicalJson(json))).toString();
  }

  static SyncSnapshot fromJson(Map<String, Object?> json) {
    if (json['format'] != kSyncFormat) {
      throw const FormatException('Vibe Terminal 동기화 파일이 아닙니다.');
    }
    final version = json['version'];
    if (version == 2) return _fromV2(json);
    if (version is! int || version > kSyncVersion) {
      throw const FormatException('이 앱보다 새 버전이 만든 동기화 파일입니다. 앱을 업데이트하세요.');
    }
    final sections = <String, List<SyncRecord>>{};
    final rawSections = json['sections'];
    if (rawSections is Map) {
      for (final entry in rawSections.entries) {
        final name = entry.key;
        final records = entry.value;
        if (name is! String || records is! List) continue;
        sections[name] = [for (final raw in records) ?SyncRecord.fromJson(raw)];
      }
    }
    final rawTombstones = json['tombstones'];
    return SyncSnapshot(
      settings: SyncSettingsBlock.fromJson(json['settings']),
      sections: sections,
      tombstones: [
        if (rawTombstones is List)
          for (final raw in rawTombstones) ?SyncTombstone.fromJson(raw),
      ],
    );
  }

  /// 업로드 전용이던 v2 스냅샷을 삭제 기록 없는 v3로 읽는다.
  static SyncSnapshot _fromV2(Map<String, Object?> json) {
    final data = json['data'] is Map
        ? Map<String, Object?>.from(json['data'] as Map)
        : const <String, Object?>{};
    Map<String, Object?> secrets(String key) => data[key] is Map
        ? Map<String, Object?>.from(data[key] as Map)
        : const <String, Object?>{};
    final keySecrets = secrets('keySecrets');
    final identitySecrets = secrets('identitySecrets');

    List<SyncRecord> records(
      String key, {
      required String Function(Map<String, Object?> item) id,
      String updatedAtKey = 'updatedAt',
      Map<String, Object?> Function(Map<String, Object?> item)? transform,
    }) {
      final raw = data[key];
      if (raw is! List) return const [];
      final result = <SyncRecord>[];
      for (final value in raw) {
        if (value is! Map) continue;
        final item = Map<String, Object?>.from(value);
        final updatedAt = _parseDate(item[updatedAtKey]);
        final recordId = id(item);
        if (updatedAt == null || recordId.isEmpty) continue;
        final recordData = transform == null ? item : transform(item);
        result.add(
          SyncRecord(
            id: recordId,
            updatedAt: updatedAt,
            data: Map.of(recordData)
              ..remove('id')
              ..remove('updatedAt'),
          ),
        );
      }
      return result;
    }

    Map<String, Object?> withSecret(
      Map<String, Object?> item,
      String refKey,
      Map<String, Object?> source,
    ) {
      final secret = source[item[refKey]];
      return {...item, if (secret is String) 'secret': secret};
    }

    String stringId(Map<String, Object?> item) => item['id'] as String? ?? '';

    final rawSettings = json['settings'];
    return SyncSnapshot(
      settings: rawSettings is Map
          ? SyncSettingsBlock(
              updatedAt: _parseDate(json['createdAt']),
              values: SyncedSettings.pick(
                Map<String, Object?>.from(rawSettings),
              ),
            )
          : null,
      sections: {
        SyncSectionNames.hosts: records(
          'hosts',
          id: stringId,
        ).where((r) => r.data['connectionType'] != 'localShell').toList(),
        SyncSectionNames.snippets: records('snippets', id: stringId),
        SyncSectionNames.memos: records(
          'memos',
          id: (item) => item['hostId'] as String? ?? '',
          transform: (item) => Map.of(item)..remove('hostId'),
        ),
        SyncSectionNames.sshKeys: records(
          'sshKeys',
          id: stringId,
          transform: (item) => withSecret(item, 'secretRef', keySecrets),
        ),
        SyncSectionNames.identities: records(
          'identities',
          id: stringId,
          transform: (item) => withSecret(item, 'secretRef', identitySecrets),
        ),
        SyncSectionNames.hostKeys: records(
          'hostKeys',
          id: (item) {
            final hostname = item['hostname'];
            final port = item['port'];
            if (hostname is! String || port is! num) return '';
            return hostKeyRecordId(hostname, port.toInt());
          },
          updatedAtKey: 'pinnedAt',
          transform: (item) => Map.of(item)
            ..remove('pinnedAt')
            ..remove('lastSeenAt'),
        ),
      },
    );
  }
}

/// 호스트 키 행 id. `HostKeyStore`와 같은 규칙(길이 접두사로 IPv6 콜론 충돌 방지).
String hostKeyRecordId(String hostname, int port) =>
    '${hostname.length}:$hostname:$port';

/// 키를 정렬한 JSON. 같은 내용이면 항상 같은 문자열이 된다.
String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return [for (final item in value) _canonical(item)];
  return value;
}

List<SyncRecord> _sortedRecords(List<SyncRecord> records) =>
    [...records]..sort((a, b) => a.id.compareTo(b.id));

List<SyncTombstone> _sortedTombstones(List<SyncTombstone> tombstones) =>
    [...tombstones]..sort((a, b) => a.key.compareTo(b.key));

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
