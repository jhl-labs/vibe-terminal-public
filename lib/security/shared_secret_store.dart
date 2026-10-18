import 'secure_store.dart';

/// Namespaces exclusively owned by synchronized SSH credentials.
/// `cred-` is retained for host credentials migrated by older app versions.
bool isSharedSecretReference(String reference) =>
    reference.length <= 512 &&
    !reference.contains('\u0000') &&
    const ['cred-', 'sshkey-', 'identity-'].any(
      (prefix) =>
          reference.startsWith(prefix) && reference.length > prefix.length,
    );

class SharedSecretStore implements SecureStore {
  SharedSecretStore(this._store);
  final SecureStore _store;

  static void validate(String reference) {
    if (!isSharedSecretReference(reference)) {
      throw const FormatException('허용되지 않은 공유 인증정보 참조입니다. 인증정보를 다시 등록하세요.');
    }
  }

  @override
  Future<String?> readSecret(String ref) {
    validate(ref);
    return _store.readSecret(ref);
  }

  @override
  Future<void> writeSecret(String ref, String value) {
    validate(ref);
    return _store.writeSecret(ref, value);
  }

  @override
  Future<void> deleteSecret(String ref) {
    validate(ref);
    return _store.deleteSecret(ref);
  }
}
