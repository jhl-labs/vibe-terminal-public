import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../data/db/app_database.dart';

enum HostKeyVerdict { trustedNew, trustedKnown, mismatch }

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
}
