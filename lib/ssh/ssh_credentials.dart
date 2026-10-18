import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

class PublicKeyCredential {
  const PublicKeyCredential({required this.privateKeyPem, this.passphrase});

  final String privateKeyPem;
  final String? passphrase;
}

class SshCredentialPayload {
  static const _typeKey = 'type';
  static const _publicKeyType = 'publicKey';
  static const _privateKeyPemKey = 'privateKeyPem';
  static const _passphraseKey = 'passphrase';

  static String password(String password) => password;

  static Future<String> publicKeyAsync({
    required String privateKeyPem,
    String? passphrase,
  }) => compute(_encodePublicKeyCredential, (privateKeyPem, passphrase));

  static String publicKey({required String privateKeyPem, String? passphrase}) {
    try {
      validatePublicKey(privateKeyPem, passphrase: passphrase);
    } catch (e) {
      throw FormatException('invalid private key: $e');
    }
    return jsonEncode({
      _typeKey: _publicKeyType,
      _privateKeyPemKey: privateKeyPem,
      if (passphrase != null && passphrase.isNotEmpty)
        _passphraseKey: passphrase,
    });
  }

  static void validatePublicKey(String privateKeyPem, {String? passphrase}) {
    final normalizedPassphrase = passphrase == null || passphrase.isEmpty
        ? null
        : passphrase;
    final keys = SSHKeyPair.fromPem(privateKeyPem, normalizedPassphrase);
    if (keys.isEmpty) {
      throw const FormatException('private key does not contain identities');
    }
    for (final key in keys) {
      key.sign(Uint8List(0));
    }
  }

  static PublicKeyCredential publicKeyFromSecret(String secret) {
    final decoded = jsonDecode(secret);
    if (decoded is! Map<String, Object?> ||
        decoded[_typeKey] != _publicKeyType) {
      throw const FormatException('invalid public key credential payload');
    }

    final privateKeyPem = decoded[_privateKeyPemKey];
    if (privateKeyPem is! String || privateKeyPem.trim().isEmpty) {
      throw const FormatException('private key is missing');
    }

    final passphraseValue = decoded[_passphraseKey];
    if (passphraseValue != null && passphraseValue is! String) {
      throw const FormatException('passphrase must be a string');
    }

    return PublicKeyCredential(
      privateKeyPem: privateKeyPem,
      passphrase: passphraseValue as String?,
    );
  }
}

String _encodePublicKeyCredential((String, String?) input) =>
    SshCredentialPayload.publicKey(
      privateKeyPem: input.$1,
      passphrase: input.$2,
    );
