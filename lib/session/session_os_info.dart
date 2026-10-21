import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/host.dart';
import '../ssh/remote_server_info.dart';
import '../state/providers.dart';
import 'session.dart';

/// 세션 id로 연결된 SSH 서버의 정보를 읽는 함수(테스트에서 교체 가능).
typedef RemoteServerInfoFetcher =
    Future<RemoteServerInfo?> Function(String sessionId);

final remoteServerInfoFetcherProvider = Provider<RemoteServerInfoFetcher>(
  (ref) => ref.read(sessionManagerProvider.notifier).remoteServerInfo,
);

enum SessionOsLookupStatus { loading, loaded, failed }

/// 한 연결([connectedAt])에 대한 원격 OS 조회 결과.
class SessionOsLookup {
  const SessionOsLookup._(this.status, this.connectedAt, this.operatingSystem);

  const SessionOsLookup.loading(DateTime? connectedAt)
    : this._(SessionOsLookupStatus.loading, connectedAt, null);

  const SessionOsLookup.loaded(DateTime? connectedAt, String operatingSystem)
    : this._(SessionOsLookupStatus.loaded, connectedAt, operatingSystem);

  const SessionOsLookup.failed(DateTime? connectedAt)
    : this._(SessionOsLookupStatus.failed, connectedAt, null);

  final SessionOsLookupStatus status;
  final DateTime? connectedAt;
  final String? operatingSystem;
}

/// 세션 정보 툴팁에 보일 원격 OS(`uname -srm`)를 세션별로 캐시한다.
///
/// 원격 명령은 연결된 SSH(쿠버네티스 SSH 포함) 세션에서만, 한 연결당 한 번만
/// 실행한다. 재연결하면([SessionInfo.connectedAt]이 바뀌면) 다시 읽는다.
/// 닫힌 세션의 항목은 지운다.
class SessionOsInfoController extends Notifier<Map<String, SessionOsLookup>> {
  @override
  Map<String, SessionOsLookup> build() {
    ref.listen<List<SessionInfo>>(sessionManagerProvider, (_, sessions) {
      final ids = sessions.map((session) => session.id).toSet();
      if (state.keys.every(ids.contains)) return;
      state = {
        for (final entry in state.entries)
          if (ids.contains(entry.key)) entry.key: entry.value,
      };
    });
    return const {};
  }

  /// [session]의 원격 OS를 아직 이번 연결에서 읽지 않았으면 읽기 시작한다.
  void ensureLoaded(SessionInfo session) {
    if (session.host.isLocalShell ||
        session.status != SessionStatus.connected) {
      return;
    }
    final existing = state[session.id];
    if (existing != null && existing.connectedAt == session.connectedAt) {
      return;
    }
    final connectedAt = session.connectedAt;
    state = {...state, session.id: SessionOsLookup.loading(connectedAt)};
    unawaited(_load(session.id, connectedAt));
  }

  Future<void> _load(String sessionId, DateTime? connectedAt) async {
    RemoteServerInfo? info;
    try {
      info = await ref.read(remoteServerInfoFetcherProvider)(sessionId);
    } catch (_) {
      info = null;
    }
    if (!ref.mounted) return;
    // 그 사이 재연결·닫힘으로 다른 조회가 시작됐으면 버린다.
    if (state[sessionId]?.connectedAt != connectedAt) return;
    final os = info?.operatingSystem;
    state = {
      ...state,
      sessionId: os == null
          ? SessionOsLookup.failed(connectedAt)
          : SessionOsLookup.loaded(connectedAt, os),
    };
  }
}

final sessionOsInfoProvider =
    NotifierProvider<SessionOsInfoController, Map<String, SessionOsLookup>>(
      SessionOsInfoController.new,
    );

/// 로컬 셸 세션의 OS 이름. 이 기기의 OS를 쓰고, Windows의 WSL 셸은 Linux다.
/// [operatingSystem]은 테스트용이며 기본값은 현재 플랫폼이다.
String localOperatingSystemLabel(Host host, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  if (os == 'windows' && host.localShellType == LocalShellType.wsl) {
    return 'Linux (WSL)';
  }
  return switch (os) {
    'windows' => 'Windows',
    'macos' => 'macOS',
    'linux' => 'Linux',
    'android' => 'Android',
    'ios' => 'iOS',
    _ => os,
  };
}

/// 연결 종류 이름. 로컬 셸은 Windows에서만 셸 종류(PowerShell/cmd/WSL)를
/// 붙인다. 다른 플랫폼은 기기 기본 셸을 쓰기 때문이다.
String sessionConnectionKindLabel(Host host, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  return switch (host.connectionType) {
    HostConnectionType.ssh => 'SSH',
    HostConnectionType.kubernetesSsh => 'Kubernetes SSH',
    HostConnectionType.localShell =>
      os == 'windows' ? '로컬 셸 · ${host.localShellType.label}' : '로컬 셸',
  };
}
