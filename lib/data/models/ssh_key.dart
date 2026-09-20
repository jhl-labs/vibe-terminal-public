import 'package:freezed_annotation/freezed_annotation.dart';

part 'ssh_key.freezed.dart';

enum SshKeySource { generated, imported }

/// 키체인에 저장된 SSH 개인키. 본문은 secure store에 [secretRef]로 둔다
/// (페이로드 형식은 `SshCredentialPayload.publicKey`와 같다).
@freezed
abstract class SshKey with _$SshKey {
  const SshKey._();

  const factory SshKey({
    required String id,
    required String name,
    required String keyType,
    required String publicKey,
    required String fingerprint,
    required String secretRef,
    @Default(SshKeySource.imported) SshKeySource source,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _SshKey;

  /// 목록에 보여줄 짧은 지문(`SHA256:` 뒤 12자).
  String get shortFingerprint {
    final body = fingerprint.startsWith('SHA256:')
        ? fingerprint.substring(7)
        : fingerprint;
    return body.length <= 12 ? body : '${body.substring(0, 12)}…';
  }
}
