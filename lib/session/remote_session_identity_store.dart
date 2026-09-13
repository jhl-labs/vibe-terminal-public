import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';
import '../ssh/remote_session_identity.dart';

typedef ApplicationSupportDirectory = Future<Directory> Function();

/// 이 Vibe Terminal 설치가 만든 원격 작업을 식별하는 안정적인 소유자 ID.
///
/// 자격증명이나 보안 토큰은 아니며, 다른 설치가 만든 작업을 자동 정리하지
/// 않도록 소유 범위를 구분하는 표식이다.
class RemoteSessionIdentityStore {
  RemoteSessionIdentityStore({ApplicationSupportDirectory? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final ApplicationSupportDirectory _directory;
  final Random _random = Random.secure();
  Future<String>? _pending;

  Future<String> readOrCreate() => _pending ??= _readOrCreate();

  Future<String> _readOrCreate() async {
    final directory = await _directory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}remote_session_owner_id',
    );
    try {
      if (file.existsSync()) {
        final stored = (await file.readAsString()).trim();
        if (RemoteSessionIdentity.isValidOwnerId(stored)) return stored;
      }
    } catch (_) {
      // 손상되거나 읽을 수 없으면 새 식별자로 복구한다.
    }

    final generated = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await writeFileAtomically(file, generated);
    return generated;
  }
}
