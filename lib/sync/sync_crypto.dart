import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class EncryptedSyncBlob {
  const EncryptedSyncBlob({
    required this.version,
    required this.algorithm,
    required this.kdf,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.mac,
    required this.cipherText,
  });

  final int version;
  final String algorithm;
  final String kdf;
  final int iterations;
  final String salt;
  final String nonce;
  final String mac;
  final String cipherText;

  Map<String, Object?> toJson() => {
    'version': version,
    'algorithm': algorithm,
    'kdf': kdf,
    'iterations': iterations,
    'salt': salt,
    'nonce': nonce,
    'mac': mac,
    'cipherText': cipherText,
  };

  factory EncryptedSyncBlob.fromJson(Map<String, Object?> json) {
    return EncryptedSyncBlob(
      version: json['version'] as int,
      algorithm: json['algorithm'] as String,
      kdf: json['kdf'] as String,
      iterations: json['iterations'] as int,
      salt: json['salt'] as String,
      nonce: json['nonce'] as String,
      mac: json['mac'] as String,
      cipherText: json['cipherText'] as String,
    );
  }
}

class SyncCryptoService {
  SyncCryptoService({AesGcm? cipher, int? iterations, Random? random})
    : _cipher = cipher ?? AesGcm.with256bits(),
      iterations = iterations ?? defaultIterations,
      _random = random ?? Random.secure();

  /// OWASP가 PBKDF2-HMAC-SHA256에 권고하는 반복 횟수. 봉투에 실제 사용한
  /// 값이 함께 들어가고 복호화는 그 값을 따르므로, 이 값을 올려도 예전
  /// 스냅샷은 계속 열린다.
  static const defaultIterations = 600000;

  /// 남이 만든 봉투의 반복 횟수를 그대로 믿으면 터무니없이 큰 값으로 앱을
  /// 묶어둘 수 있으므로 상한을 둔다.
  static const maxAcceptedIterations = 5000000;

  static const _version = 1;
  static const _algorithm = 'aes-256-gcm';
  static const _kdfName = 'pbkdf2-hmac-sha256';

  /// 새로 암호화할 때 쓸 반복 횟수. 테스트에서 낮춰 주입할 수 있다.
  final int iterations;

  final AesGcm _cipher;
  final Random _random;

  Future<EncryptedSyncBlob> encryptJson(
    Map<String, Object?> json,
    String encryptionKey,
  ) async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final secretKey = await _deriveKey(encryptionKey, salt, iterations);
    final plainText = utf8.encode(const JsonEncoder().convert(json));
    final box = await _cipher.encrypt(
      plainText,
      secretKey: secretKey,
      nonce: nonce,
    );
    return EncryptedSyncBlob(
      version: _version,
      algorithm: _algorithm,
      kdf: _kdfName,
      iterations: iterations,
      salt: base64Encode(salt),
      nonce: base64Encode(box.nonce),
      mac: base64Encode(box.mac.bytes),
      cipherText: base64Encode(box.cipherText),
    );
  }

  Future<Map<String, Object?>> decryptJson(
    EncryptedSyncBlob blob,
    String encryptionKey,
  ) async {
    if (blob.version != _version ||
        blob.algorithm != _algorithm ||
        blob.kdf != _kdfName) {
      throw const FormatException('Unsupported sync encryption envelope');
    }
    // 반복 횟수는 반드시 봉투에 적힌 값을 써야 한다. 현재 기본값으로 유도하면
    // 다른 반복 횟수로 만들어진 예전 스냅샷을 영영 열 수 없게 된다.
    if (blob.iterations <= 0 || blob.iterations > maxAcceptedIterations) {
      throw const FormatException(
        'Sync envelope iteration count is out of range',
      );
    }
    final salt = base64Decode(blob.salt);
    final secretKey = await _deriveKey(encryptionKey, salt, blob.iterations);
    final clearText = await _cipher.decrypt(
      SecretBox(
        base64Decode(blob.cipherText),
        nonce: base64Decode(blob.nonce),
        mac: Mac(base64Decode(blob.mac)),
      ),
      secretKey: secretKey,
    );
    final decoded = jsonDecode(utf8.decode(clearText));
    if (decoded is! Map) {
      throw const FormatException('Sync snapshot root must be an object');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<SecretKey> _deriveKey(
    String encryptionKey,
    List<int> salt,
    int iterations,
  ) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(encryptionKey)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
