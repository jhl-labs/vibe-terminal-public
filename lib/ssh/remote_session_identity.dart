class RemoteSessionIdentity {
  const RemoteSessionIdentity._();

  static final _ownerPattern = RegExp(r'^[a-f0-9]{16}$');
  static final _sessionPattern = RegExp(r'^[a-f0-9]{32}$');
  static final _versionedPattern = RegExp(
    r'^r1_([a-f0-9]{16})_([a-f0-9]{32})$',
  );

  static String compose({required String ownerId, required String sessionId}) {
    if (!_ownerPattern.hasMatch(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId', '올바르지 않은 설치 식별자입니다.');
    }
    if (!_sessionPattern.hasMatch(sessionId)) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        '올바르지 않은 원격 세션 식별자입니다.',
      );
    }
    return 'r1_${ownerId}_$sessionId';
  }

  static String? ownerIdOf(String remoteSessionId) =>
      _versionedPattern.firstMatch(remoteSessionId)?.group(1);

  static bool isValidOwnerId(String value) => _ownerPattern.hasMatch(value);

  static bool isVersioned(String value) => _versionedPattern.hasMatch(value);
}
