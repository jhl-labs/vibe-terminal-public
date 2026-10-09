import 'package:drift/drift.dart';

import '../../security/secure_store.dart';
import '../../security/ssh_key_material.dart';
import '../../ssh/ssh_credentials.dart';
import '../db/app_database.dart';
import '../models/ssh_key.dart';

/// 같은 지문의 키가 이미 존재할 때 던진다. [existing]으로 기존 키를 알려준다.
class DuplicateSshKeyException implements Exception {
  const DuplicateSshKeyException(this.existing);
  final SshKey existing;
  @override
  String toString() => '같은 지문의 키가 이미 있습니다: ${existing.name}';
}

/// 이 키를 참조하는 Identity가 있어 삭제할 수 없을 때 던진다.
class SshKeyInUseException implements Exception {
  const SshKeyInUseException(this.count);
  final int count;
  @override
  String toString() => '이 키를 사용하는 Identity가 $count개 있습니다';
}

/// SSH 개인키 메타데이터(DB)와 실제 키 자료(secure store)를 함께 관리한다.
class SshKeyRepository {
  SshKeyRepository(this._db, this._secureStore);
  final AppDatabase _db;
  final SecureStore _secureStore;

  Future<List<SshKey>> getAll() async {
    final rows = await (_db.select(
      _db.sshKeys,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    return rows.map(_toModel).toList();
  }

  Future<SshKey?> getById(String id) async {
    final row = await (_db.select(
      _db.sshKeys,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<SshKey?> findByFingerprint(String fingerprint) async {
    // 다른 기기에서 같은 키를 따로 가져와 동기화되면 같은 값이 둘 이상일 수 있다.
    final row =
        await (_db.select(_db.sshKeys)
              ..where((t) => t.fingerprint.equals(fingerprint))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<SshKey?> findBySecretRef(String secretRef) async {
    // 다른 기기에서 같은 키를 따로 가져와 동기화되면 같은 값이 둘 이상일 수 있다.
    final row =
        await (_db.select(_db.sshKeys)
              ..where((t) => t.secretRef.equals(secretRef))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// PEM을 검증해 키를 저장한다. [secretRef]를 주면 이미 secure store에 있는
  /// 비밀(기존 호스트 credentialRef)을 그대로 참조한다 — 마이그레이션용.
  Future<SshKey> create({
    required String name,
    required String privateKeyPem,
    String? passphrase,
    SshKeySource source = SshKeySource.imported,
    String? secretRef,
  }) async {
    // 잘못된 PEM이면 FormatException이 그대로 전파된다.
    final material = SshKeyMaterial.parse(
      privateKeyPem,
      passphrase: passphrase,
    );
    final existing = await findByFingerprint(material.fingerprint);
    if (existing != null) throw DuplicateSshKeyException(existing);

    final now = DateTime.now();
    final id = 'key-${now.microsecondsSinceEpoch}';
    final ref = secretRef ?? 'sshkey-$id';
    if (secretRef == null) {
      await _secureStore.writeSecret(
        ref,
        SshCredentialPayload.publicKey(
          privateKeyPem: privateKeyPem,
          passphrase: passphrase,
        ),
      );
    }
    final key = SshKey(
      id: id,
      name: name.trim().isEmpty ? material.comment : name.trim(),
      keyType: material.keyType,
      publicKey: material.publicKeyLine,
      fingerprint: material.fingerprint,
      secretRef: ref,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.sshKeys).insert(_toRow(key));
    return key;
  }

  Future<void> rename(String id, String name) async {
    await (_db.update(_db.sshKeys)..where((t) => t.id.equals(id))).write(
      SshKeysCompanion(
        name: Value(name.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// secure store에서 개인키 원본을 읽어 SSH 접속에 쓸 수 있는 형태로 돌려준다.
  Future<PublicKeyCredential?> readPrivateKey(SshKey key) async {
    final secret = await _secureStore.readSecret(key.secretRef);
    if (secret == null || secret.isEmpty) return null;
    return SshCredentialPayload.publicKeyFromSecret(secret);
  }

  /// 이 키를 참조하는 Identity 개수.
  Future<int> usageCount(String id) async {
    final count = _db.identities.id.count();
    final row =
        await (_db.selectOnly(_db.identities)
              ..addColumns([count])
              ..where(_db.identities.keyId.equals(id)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> delete(String id) async {
    final used = await usageCount(id);
    if (used > 0) throw SshKeyInUseException(used);
    final key = await getById(id);
    if (key == null) return;
    await (_db.delete(_db.sshKeys)..where((t) => t.id.equals(id))).go();
    // 같은 비밀을 가리키는 다른 키(동기화로 들어온 중복)가 있으면 남긴다.
    if (await findBySecretRef(key.secretRef) == null) {
      await _secureStore.deleteSecret(key.secretRef);
    }
  }

  SshKey _toModel(SshKeyRow r) => SshKey(
    id: r.id,
    name: r.name,
    keyType: r.keyType,
    publicKey: r.publicKey,
    fingerprint: r.fingerprint,
    secretRef: r.secretRef,
    source: r.source >= 0 && r.source < SshKeySource.values.length
        ? SshKeySource.values[r.source]
        : SshKeySource.imported,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );

  SshKeysCompanion _toRow(SshKey k) => SshKeysCompanion.insert(
    id: k.id,
    name: k.name,
    keyType: k.keyType,
    publicKey: k.publicKey,
    fingerprint: k.fingerprint,
    secretRef: k.secretRef,
    source: Value(k.source.index),
    createdAt: k.createdAt,
    updatedAt: k.updatedAt,
  );
}
