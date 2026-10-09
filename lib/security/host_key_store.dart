import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../data/db/app_database.dart';

enum HostKeyVerdict { trustedNew, trustedKnown, mismatch }

/// known_hosts 가져오기 결과: 가져온 항목 수와 건너뛴 줄 수.
class KnownHostsImportResult {
  const KnownHostsImportResult({required this.imported, required this.skipped});
  final int imported;
  final int skipped;
}

class HostKeyStore {
  HostKeyStore(this._db);
  final AppDatabase _db;

  /// dartssh2 호환 지문을 반환한다: `SHA256:<unpadded-base64>` 형식.
  /// dartssh2는 padding 없는 base64를 사용하므로 `=` 제거.
  String fingerprintOf(List<int> keyBytes) {
    final digest = sha256.convert(keyBytes);
    final b64 = base64.encode(digest.bytes).replaceAll('=', '');
    return 'SHA256:$b64';
  }

  // 길이 프리픽스로 hostname:port 경계를 명확히 해 IPv6 등 콜론 포함 호스트명 충돌 방지
  String _id(String hostname, int port) => '${hostname.length}:$hostname:$port';

  Future<HostKeyVerdict> verify({
    required String hostname,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final row =
        await (_db.select(_db.hostKeys)
              ..where((t) => t.hostname.equals(hostname) & t.port.equals(port)))
            .getSingleOrNull();
    if (row == null) return HostKeyVerdict.trustedNew;
    return row.fingerprint == fingerprint
        ? HostKeyVerdict.trustedKnown
        : HostKeyVerdict.mismatch;
  }

  Future<void> pin({
    required String hostname,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    await _db
        .into(_db.hostKeys)
        .insertOnConflictUpdate(
          HostKeysCompanion.insert(
            id: _id(hostname, port),
            hostname: hostname,
            port: port,
            keyType: keyType,
            fingerprint: fingerprint,
            pinnedAt: DateTime.now(),
          ),
        );
  }

  /// 저장된 지문을 반환한다. 핀된 키가 없으면 null.
  Future<String?> storedFingerprint({
    required String hostname,
    required int port,
  }) async {
    final row =
        await (_db.select(_db.hostKeys)
              ..where((t) => t.hostname.equals(hostname) & t.port.equals(port)))
            .getSingleOrNull();
    return row?.fingerprint;
  }

  /// 핀된 모든 호스트키를 호스트명순으로 반환한다.
  Future<List<HostKeyRow>> listAll() => (_db.select(
    _db.hostKeys,
  )..orderBy([(t) => OrderingTerm.asc(t.hostname)])).get();

  /// 핀된 호스트키를 삭제한다.
  Future<void> remove({required String hostname, required int port}) =>
      (_db.delete(
        _db.hostKeys,
      )..where((t) => t.hostname.equals(hostname) & t.port.equals(port))).go();

  /// 핀된 키와 일치하는 연결이 성공했을 때 호출한다.
  ///
  /// 마지막 접속 시각은 기기별 값이라 동기화하지 않는다. drift의 변경 알림을
  /// 내지 않는 SQL로 써서, 접속할 때마다 동기화가 예약되지 않게 한다.
  Future<void> touch({required String hostname, required int port}) =>
      _db.customStatement(
        'UPDATE host_keys SET last_seen_at = ? WHERE hostname = ? AND port = ?',
        [DateTime.now().millisecondsSinceEpoch ~/ 1000, hostname, port],
      );

  /// OpenSSH `known_hosts` 텍스트를 가져온다. 첫 호스트 이름만 쓰고(별칭 무시),
  /// 해시(`|1|`)·마커(`@…`)·형식이 깨진 줄은 건너뛴다.
  Future<KnownHostsImportResult> importOpenSshKnownHosts(String content) async {
    var imported = 0;
    var skipped = 0;
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (line.startsWith('@') || line.startsWith('|') || parts.length < 3) {
        skipped++;
        continue;
      }
      final target = _parseHostPort(parts[0].split(',').first);
      final List<int> keyBytes;
      try {
        keyBytes = base64.decode(parts[2]);
      } on FormatException {
        skipped++;
        continue;
      }
      await pin(
        hostname: target.$1,
        port: target.$2,
        keyType: parts[1],
        fingerprint: fingerprintOf(keyBytes),
      );
      imported++;
    }
    return KnownHostsImportResult(imported: imported, skipped: skipped);
  }

  /// `[host]:port` → (host, port), 그 외 → (host, 22).
  (String, int) _parseHostPort(String token) {
    final match = RegExp(r'^\[(.+)\]:(\d+)$').firstMatch(token);
    if (match != null) {
      return (match.group(1)!, int.parse(match.group(2)!));
    }
    return (token, 22);
  }
}
