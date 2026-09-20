import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';

/// 개인키 PEM에서 목록·지문·서버 등록에 필요한 공개 정보만 뽑아낸다.
class SshKeyMaterial {
  const SshKeyMaterial({
    required this.keyType,
    required this.publicKeyLine,
    required this.fingerprint,
    required this.comment,
  });

  final String keyType;

  /// `ssh-ed25519 AAAA… comment` — authorized_keys 한 줄.
  final String publicKeyLine;

  /// `SHA256:<unpadded-base64>` — HostKeyStore.fingerprintOf와 같은 형식.
  final String fingerprint;
  final String comment;

  static SshKeyMaterial parse(String pem, {String? passphrase}) {
    final normalized = passphrase == null || passphrase.isEmpty
        ? null
        : passphrase;
    final List<SSHKeyPair> pairs;
    try {
      pairs = SSHKeyPair.fromPem(pem, normalized);
    } catch (e) {
      throw FormatException('invalid private key: $e');
    }
    if (pairs.isEmpty) {
      throw const FormatException('private key does not contain identities');
    }
    final pair = pairs.first;
    final encoded = pair.toPublicKey().encode();
    final comment = pair is OpenSSHEd25519KeyPair ? pair.comment : '';
    final digest = sha256.convert(encoded);
    final b64 = base64.encode(digest.bytes).replaceAll('=', '');
    return SshKeyMaterial(
      keyType: pair.name,
      publicKeyLine: [
        pair.name,
        base64.encode(encoded),
        if (comment.isNotEmpty) comment,
      ].join(' '),
      fingerprint: 'SHA256:$b64',
      comment: comment,
    );
  }
}
