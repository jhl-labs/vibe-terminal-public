import 'dart:convert';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;

import 'sync_crypto.dart';
import 'sync_local_store.dart';
import 'sync_merge.dart';
import 'sync_remote.dart';
import 'sync_snapshot.dart';

/// 원격 파일을 이 기기의 암호화 키로 열 수 없다.
class SyncWrongKeyException implements Exception {
  const SyncWrongKeyException();

  @override
  String toString() => '암호화 키가 다릅니다. 처음 동기화한 기기에서 쓴 키를 똑같이 입력하세요.';
}

/// 원격 파일이 동기화 파일 형식이 아니다.
class SyncRemoteFormatException implements Exception {
  const SyncRemoteFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 이 저장소와 처음 동기화하는데 양쪽에 데이터가 있다. 합치기 전에 확인을 받는다.
class SyncNeedsConfirmationException implements Exception {
  const SyncNeedsConfirmationException({
    required this.localCount,
    required this.remoteCount,
  });

  final int localCount;
  final int remoteCount;

  @override
  String toString() =>
      '원격 $remoteCount개와 이 기기의 $localCount개를 합칩니다. 확인 후 진행하세요.';
}

/// 다시 받아도 계속 다른 기기와 겹쳤다.
class SyncRetryExhaustedException implements Exception {
  const SyncRetryExhaustedException();

  @override
  String toString() => '다른 기기와 동기화가 계속 겹쳤습니다.';
}

/// 마지막으로 맞춘 원격 파일과 로컬 상태. 둘 다 그대로면 병합을 건너뛴다.
class SyncCheckpoint {
  const SyncCheckpoint({
    required this.remoteSha,
    required this.localFingerprint,
  });

  final String? remoteSha;
  final String localFingerprint;
}

class SyncRunResult {
  const SyncRunResult({
    required this.pulled,
    required this.pushed,
    required this.checkpoint,
  });

  /// 이 기기에 반영한 항목 수.
  final int pulled;

  /// 원격에 올린 항목 수.
  final int pushed;

  final SyncCheckpoint checkpoint;
}

/// 내려받기 → 병합 → 로컬 적용 → 업로드를 한 번 실행한다.
class SyncEngine {
  SyncEngine({
    required this._local,
    required this._remote,
    required this._crypto,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncLocalStore _local;
  final SyncRemote _remote;
  final SyncCryptoService _crypto;
  final DateTime Function() _clock;

  static const maxAttempts = 3;

  /// [initial]이면 이 저장소와 처음 맞추는 것이다. 이때 양쪽에 데이터가 있고
  /// [confirmed]가 아니면 [SyncNeedsConfirmationException]을 던진다.
  ///
  /// [onApplied]는 로컬에 무언가를 반영할 때마다 바로 불린다. 그 뒤 업로드가
  /// 실패해도 로컬은 이미 바뀌었으므로, 화면 갱신은 여기에 맞춘다.
  Future<SyncRunResult> run({
    required String encryptionKey,
    required bool initial,
    bool confirmed = false,
    SyncCheckpoint? checkpoint,
    void Function(int changed)? onApplied,
  }) async {
    var pulled = 0;
    var pushed = 0;
    var attempts = maxAttempts;
    var anotherPassUsed = false;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final file = await _remote.download();
      final local = await _local.read();
      if (!initial &&
          checkpoint != null &&
          file?.sha == checkpoint.remoteSha &&
          local.fingerprint == checkpoint.localFingerprint) {
        return SyncRunResult(pulled: 0, pushed: 0, checkpoint: checkpoint);
      }

      final remoteBlob = file == null ? null : _parseBlob(file.content);
      final remote = remoteBlob == null
          ? SyncSnapshot.empty
          : await _decrypt(remoteBlob, encryptionKey);
      // 이 앱이 다루지 않는 섹션은 보존만 하므로 확인 문구의 개수에서 뺀다.
      final remoteCount = _knownRecordCount(remote, local.snapshot);
      if (initial &&
          !confirmed &&
          local.snapshot.recordCount > 0 &&
          remoteCount > 0) {
        throw SyncNeedsConfirmationException(
          localCount: local.snapshot.recordCount,
          remoteCount: remoteCount,
        );
      }

      final result = mergeSnapshots(
        local: local.snapshot,
        remote: remote,
        now: _clock(),
        initial: initial,
      );
      // 체크포인트 지문은 적용 직후 값이어야 한다. 업로드를 기다리는 사이의
      // 로컬 변경까지 담으면 다음 실행이 그 변경을 올리지 않고 건너뛴다.
      final SyncApplied applied;
      try {
        applied = await _local.apply(
          result,
          expectedFingerprint: local.fingerprint,
        );
      } on SyncLocalChangedException {
        continue;
      }
      pulled += applied.changed;
      if (applied.changed > 0) onApplied?.call(applied.changed);

      var remoteSha = file?.sha;
      final needsUpload =
          file == null || result.merged.contentHash != remote.contentHash;
      if (needsUpload) {
        final blob = await _crypto.encryptJson(
          result.merged.toJson(createdAt: _clock()),
          encryptionKey,
          reuse: remoteBlob,
        );
        try {
          remoteSha = await _remote.upload(
            jsonEncode(blob.toJson()),
            sha: file?.sha,
          );
        } on SyncRemoteConflictException {
          continue;
        }
      }
      if (needsUpload) pushed += result.pushed;
      // 지우지 않고 남긴 행은 아직 원격에 없다. 같은 실행에서 한 번 더 합쳐
      // 바로 올린다. 겹침 재시도와 별개로 한 번만 더 돈다. 이미 합치기로 한
      // 첫 동기화이므로 다시 묻지 않는다.
      if (applied.needsAnotherPass && !anotherPassUsed) {
        anotherPassUsed = true;
        attempts++;
        confirmed = true;
        continue;
      }
      return SyncRunResult(
        pulled: pulled,
        pushed: pushed,
        checkpoint: SyncCheckpoint(
          remoteSha: remoteSha,
          localFingerprint: applied.fingerprint,
        ),
      );
    }
    throw const SyncRetryExhaustedException();
  }

  static int _knownRecordCount(SyncSnapshot remote, SyncSnapshot local) => [
    for (final name in local.sections.keys) remote.sections[name]?.length ?? 0,
  ].fold(0, (sum, count) => sum + count);

  EncryptedSyncBlob _parseBlob(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) throw const FormatException();
      return EncryptedSyncBlob.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      throw const SyncRemoteFormatException(
        '원격 동기화 파일을 읽을 수 없습니다. 다른 파일 경로를 쓰거나 이 파일을 지우세요.',
      );
    }
  }

  Future<SyncSnapshot> _decrypt(
    EncryptedSyncBlob blob,
    String encryptionKey,
  ) async {
    final Map<String, Object?> plain;
    try {
      plain = await _crypto.decryptJson(blob, encryptionKey);
    } on SecretBoxAuthenticationError {
      throw const SyncWrongKeyException();
    }
    try {
      return SyncSnapshot.fromJson(plain);
    } on FormatException catch (e) {
      throw SyncRemoteFormatException(e.message);
    }
  }
}
