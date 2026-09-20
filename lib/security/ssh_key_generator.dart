import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
// OpenSSH 암호화 개인키 인코딩에 필요한 KDF/cipher는 dartssh2가 공개 API로
// 내놓지 않는다. 복호화 쪽(SSHKeyPair.fromPem)과 같은 구현을 써야 왕복이
// 보장되므로 내부 모듈을 직접 쓴다.
// ignore_for_file: implementation_imports
import 'package:dartssh2/src/ssh_message.dart';
import 'package:dartssh2/src/utils/bcrypt.dart';
import 'package:dartssh2/src/utils/cipher_ext.dart';

import 'ssh_key_material.dart';

/// 생성된 키 한 쌍. [privateKeyPem]은 `openssh-key-v1` PEM,
/// [publicKeyLine]은 authorized_keys 한 줄(`ssh-ed25519 AAAA… comment`).
class GeneratedSshKey {
  const GeneratedSshKey({
    required this.privateKeyPem,
    required this.publicKeyLine,
  });

  final String privateKeyPem;
  final String publicKeyLine;
}

/// Ed25519 키를 만들어 OpenSSH 개인키 포맷(`openssh-key-v1`)으로 인코딩한다.
class SshKeyGenerator {
  static const _cipherName = 'aes256-ctr';
  static const _kdfRounds = 16;
  static const _saltSize = 16;

  /// 새 Ed25519 키를 만든다. [passphrase]가 비어 있지 않으면 bcrypt KDF +
  /// aes256-ctr로 개인키를 암호화한다. 결과는 `SSHKeyPair.fromPem(pem, passphrase)`
  /// 로 다시 읽을 수 있다.
  static Future<GeneratedSshKey> generateEd25519({
    required String comment,
    String? passphrase,
  }) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final publicKey = Uint8List.fromList(
      (await keyPair.extractPublicKey()).bytes,
    );
    // OpenSSH는 개인키 필드에 seed(32) || public(32) 64바이트를 저장한다.
    final privateKey = Uint8List.fromList([...seed, ...publicKey]);
    final pair = OpenSSHEd25519KeyPair(publicKey, privateKey, comment);

    final normalized = passphrase == null || passphrase.isEmpty
        ? null
        : passphrase;
    final pem = normalized == null
        ? pair.toPem()
        : _encryptedPem(pair, normalized);
    // 생성 결과를 실제로 다시 파싱해 공개키 줄을 얻는다 — 인코딩 오류가 있으면
    // 여기서 바로 드러난다.
    final publicKeyLine = SshKeyMaterial.parse(
      pem,
      passphrase: normalized,
    ).publicKeyLine;
    return GeneratedSshKey(privateKeyPem: pem, publicKeyLine: publicKeyLine);
  }

  /// `OpenSSHKeyPair.toPem`과 같은 개인키 블롭을 만들되 bcrypt KDF +
  /// aes256-ctr로 암호화한다. dartssh2의 `_decryptPrivateKeyBlob`이 그대로 푼다.
  static String _encryptedPem(OpenSSHEd25519KeyPair pair, String passphrase) {
    final random = Random.secure();
    final writer = SSHMessageWriter();
    final checkInt = random.nextInt(0xFFFFFFFF);
    writer.writeUint32(checkInt);
    writer.writeUint32(checkInt);
    writer.writeUtf8(pair.name);
    pair.writeTo(writer);

    final cipher = SSHCipherType.fromName(_cipherName)!;
    // 암호화 전에 블록 크기 배수까지 1,2,3,… 로 패딩한다.
    for (var i = 0; writer.length % cipher.blockSize != 0; i++) {
      writer.writeUint8(i + 1);
    }
    final plain = writer.takeBytes();

    final salt = Uint8List.fromList(
      List<int>.generate(_saltSize, (_) => random.nextInt(256)),
    );
    // 복호화 쪽(getPrivateKeys)이 Utf8Encoder로 패스프레이즈를 바꾸므로 동일하게 맞춘다.
    final passBytes = Uint8List.fromList(utf8.encode(passphrase));
    final derived = Uint8List(cipher.keySize + cipher.ivSize);
    bcrypt_pbkdf(
      passBytes,
      passBytes.length,
      salt,
      salt.length,
      derived,
      derived.length,
      _kdfRounds,
    );
    final key = Uint8List.view(derived.buffer, 0, cipher.keySize);
    final iv = Uint8List.view(derived.buffer, cipher.keySize, cipher.ivSize);
    final encrypted = cipher
        .createCipher(key, iv, forEncryption: true)
        .processAll(plain);

    return OpenSSHKeyPairs(
      cipherName: _cipherName,
      kdfName: 'bcrypt',
      kdfOptions: OpenSSHBcryptKdfOptions(salt, _kdfRounds),
      publicKeys: [pair.toPublicKey().encode()],
      privateKeyBlob: encrypted,
    ).toPem();
  }
}
