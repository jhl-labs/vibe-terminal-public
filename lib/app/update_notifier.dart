import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_preferences.dart';

/// 세션 레일 헤더의 버전 라벨 옆에 배지로 보여줄 새 버전. 없으면 null.
///
/// 시작 시 업데이트 확인 흐름([_AppRootState._checkForUpdatesOnStartup])이
/// 채우고, 사용자가 "이 버전 건너뛰기"를 고르면 비운다. `providers.dart`가
/// 아니라 여기 두는 이유는 이 상태가 업데이트 확인 모듈 밖에서는 읽기만
/// 하기 때문이다.
class PendingUpdateNotifier extends Notifier<PendingUpdate?> {
  @override
  PendingUpdate? build() => null;

  void set(PendingUpdate? value) => state = value;
}

final pendingUpdateProvider =
    NotifierProvider<PendingUpdateNotifier, PendingUpdate?>(
      PendingUpdateNotifier.new,
    );
