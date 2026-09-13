import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStore {
  Future<void> writeSecret(String ref, String value);
  Future<String?> readSecret(String ref);
  Future<void> deleteSecret(String ref);
}

class FlutterSecureStoreImpl implements SecureStore {
  FlutterSecureStoreImpl([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _storage;

  @override
  Future<void> writeSecret(String ref, String value) =>
      _storage.write(key: 'vibe-terminal-public::$ref', value: value);

  @override
  Future<String?> readSecret(String ref) =>
      _storage.read(key: 'vibe-terminal-public::$ref');

  @override
  Future<void> deleteSecret(String ref) =>
      _storage.delete(key: 'vibe-terminal-public::$ref');
}

class InMemorySecureStore implements SecureStore {
  final Map<String, String> _map = {};

  @override
  Future<void> writeSecret(String ref, String value) async => _map[ref] = value;

  @override
  Future<String?> readSecret(String ref) async => _map[ref];

  @override
  Future<void> deleteSecret(String ref) async => _map.remove(ref);
}
